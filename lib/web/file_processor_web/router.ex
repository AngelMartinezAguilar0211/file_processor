defmodule FileProcessorWeb.Router do
  use FileProcessorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FileProcessorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FileProcessorWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/process", PageController, :process
    get "/history", PageController, :history
    get "/history/:id", PageController, :history_detail
  end

  if Application.compile_env(:file_processor, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FileProcessorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
