defmodule JsErrorChannel.Repo do
  use Ecto.Repo,
    otp_app: :js_error_channel,
    adapter: Ecto.Adapters.Postgres
end
