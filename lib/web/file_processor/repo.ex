defmodule FileProcessor.Repo do
  use Ecto.Repo,
    otp_app: :file_processor,
    adapter: Ecto.Adapters.Postgres
end
