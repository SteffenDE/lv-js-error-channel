defmodule JsErrorChannelWeb.Socket do
  use Phoenix.LiveView.Socket

  channel "js-error", JsErrorChannelWeb.ErrorChannel
end
