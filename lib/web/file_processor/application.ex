defmodule FileProcessor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FileProcessorWeb.Telemetry,
      FileProcessor.Repo,
      {DNSCluster, query: Application.get_env(:file_processor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FileProcessor.PubSub},
      # Start a worker by calling: FileProcessor.Worker.start_link(arg)
      # {FileProcessor.Worker, arg},
      # Start to serve requests, typically the last entry
      FileProcessorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FileProcessor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FileProcessorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
