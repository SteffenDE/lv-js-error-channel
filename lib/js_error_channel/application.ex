defmodule JsErrorChannel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JsErrorChannelWeb.Telemetry,
      JsErrorChannel.Repo,
      {DNSCluster, query: Application.get_env(:js_error_channel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JsErrorChannel.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: JsErrorChannel.Finch},
      # Start a worker by calling: JsErrorChannel.Worker.start_link(arg)
      # {JsErrorChannel.Worker, arg},
      # Start to serve requests, typically the last entry
      JsErrorChannelWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JsErrorChannel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JsErrorChannelWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
