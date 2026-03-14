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

    # Renders the main LiveView interface for file uploading and processing
    live "/", HomeLive, :index

    # Displays the history list of processed files
    live "/history", HistoryLive, :index

    # Displays the detailed view of a specific history report
    live "/history/:id", HistoryDetailLive, :show
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
