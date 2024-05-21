defmodule JsErrorChannelWeb.ErrorChannel do
  @moduledoc false
  use Phoenix.Channel, log_handle_in: false
  require Logger
  import Bitwise

  def join(_topic, _message, socket) do
    sourcemaps = sourcemaps(socket.endpoint.config(:otp_app))
    if map_size(sourcemaps) == 0, do: Logger.info("No sourcemaps found, make sure to add: esbuild default --sourcemap")
    {:ok, assign(socket, :sourcemaps, sourcemaps)}
  end

  def handle_in("js-error", params, socket) do
    measurement = %{duration: params["measurement"]["duration"]}
    metadata = %{
      type: params["metadata"]["type"],
      message: params["metadata"]["message"],
      stacktrace: Enum.map(params["metadata"]["stacktrace"], fn
      [func, %{"file" => file, "line" => line, "col" => col} = params] = trace ->
      if file =~ ".js"  do
        uri = URI.parse(file)
        meta = socket.assigns.sourcemaps["#{Path.basename(uri.path)}.map"]["mappings"][line]
        [source, line | _] = meta[Enum.min([col | Map.keys(meta)])]
        [func, %{params | "file" => socket.assigns.sourcemaps["#{Path.basename(file)}.map"]["sources"][source], "line" => line}]
      else
        trace
      end
      end)}
    :telemetry.execute([:my_app_web, :live_view, :javascript, :exception], measurement, metadata)
    {:noreply, socket}
  end

  def list_source_maps(otp_app) do
    path = :code.priv_dir(otp_app)
    path
    |> File.ls!()
    |> list_source_maps(path, [])
  end
  def list_source_maps([], _base, acc), do: acc
  def list_source_maps([file | rest], base, acc) do
    path = Path.join(base, file)
    cond do
      File.dir?(path) -> list_source_maps(rest, base, list_source_maps(File.ls!(path), path, []) ++ acc)
      path =~ ".map" -> list_source_maps(rest, base, [path | acc])
      true -> list_source_maps(rest, base, acc)
    end
  end

  def sourcemaps(otp_app) do
    for file <- list_source_maps(otp_app), into: %{} do
      sourcemap = Jason.decode!(File.read!(file))
      {Path.basename(file), %{sourcemap |
        "mappings" => parse(sourcemap["mappings"]),
        "names" => Enum.reduce(sourcemap["names"], %{}, &Map.put(&2, map_size(&2), &1)),
        "sources" => Enum.reduce(sourcemap["sources"], %{}, &Map.put(&2, map_size(&2), &1)),
      }}
    end
  end


  @doc """
    Examples

    iex> parse("AAAA;AAAA,EAAA,OAAO,CAAC,GAAR,CAAY,aAAZ,CAAA,CAAA;AAAA")
    %{
      0 => %{0 => [0, 0, 0]},
      1 => %{
        0 => [0, 0, 0],
        2 => [0, 0, 0],
        9 => [0, 0, 7],
        10 => [0, 0, 8],
        13 => [0, 0, 0],
        14 => [0, 0, 12],
        27 => [0, 0, 0],
        28 => [0, 0, 0],
        29 => [0, 0, 0]
      },
      2 => %{0 => [0, 0, 0]}
    }
  """
  def parse(source, line \\ 0, gc \\ 0, sf \\ 0, cl \\ 0, cc \\ 0, ni \\ 0, segment \\ [], acc \\ %{})
  def parse("", line, gc, sf, cl, cc, ni, segment, acc) do
    values = decode("#{segment}")
    gc = gc + Map.get(values, 0, 0)
    sf = sf + Map.get(values, 1, 0)
    cl = cl + Map.get(values, 2, 0)
    cc = cc + Map.get(values, 3, 0)
    ni = if n = values[4], do: ni + n
    entry = %{gc => [sf, cl, cc | List.wrap(ni)]}
    Map.update(acc, line, entry, &Map.merge(&1, entry))
  end
  def parse(<<b::binary-size(1), rest::binary>>, line, gc, sf, cl, cc, ni, segment, acc) when b in ~w[, ;] do
    new_line = <<b::binary>> == ";"
    values = decode("#{segment}")
    gc = gc + Map.get(values, 0, 0)
    sf = sf + Map.get(values, 1, 0)
    cl = cl + Map.get(values, 2, 0)
    cc = cc + Map.get(values, 3, 0)
    ni = if n = values[4], do: ni + n
    entry = %{gc => [sf, cl, cc | List.wrap(ni)]}
    acc = Map.update(acc, line, entry, &Map.merge(&1, entry))
    parse(rest, (if new_line, do: line+1, else: line), (if new_line, do: 0, else: gc), sf, cl, cc, ni || 0, [], acc)
  end
  def parse(<<b::binary-size(1), rest::binary>>, line, gc, sf, cl, cc, ni, segment, acc) do
    parse(rest, line, gc, sf, cl, cc, ni, [segment] ++ [b], acc)
  end

  @doc """
    Examples

      iex> decode("AAAA")
      %{0 => 0, 1 => 0, 2 => 0, 3 => 0}
      iex> decode("AAgBC")
      %{0 => 0, 1 => 0, 2 => 16, 3 => 1}
      iex> decode("D")
      %{0 => -1}
      iex> decode("B")
      %{0 => -2147483648}
      iex> decode("+/////D")
      %{0 => 2147483647}
  """
  @base ~w[A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 + / =]
  @encoding Enum.reduce(@base, %{}, &Map.put(&2, &1, map_size(&2)))
  def decode(binary, value \\ 0, shift \\ 0, acc \\ %{})
  def decode(<<>>, _value, _shift, acc),  do: acc
  def decode(<<b::binary-size(1), rest::binary>>, value, shift, acc) when b in @base do
    int = @encoding[<<b::binary>>]
    cont = int &&& 32
    int = int &&& 31
    value = value + (int <<< shift)
    neg = value &&& 1
    case {neg !== 0, cont !== 0} do
      {_, true} -> decode(rest, value, shift + 5,  acc)
      {true, _} ->
      value = Integer.mod(value, 0x100000000) >>> 1
      decode(rest, 0, 0, Map.put(acc, map_size(acc), (if value === 0, do: -0x80000000, else: -value)))
      _         ->
      value = Integer.mod(value, 0x100000000) >>> 1
      decode(rest, 0, 0, Map.put(acc, map_size(acc), value))
    end
  end
end
