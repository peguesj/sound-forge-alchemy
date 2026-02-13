defmodule SoundForgeWeb.Router do
  use SoundForgeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SoundForgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SoundForgeWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/tracks/:id", DashboardLive, :show
    get "/files/*path", FileController, :serve
  end

  # Other scopes may use custom stacks.
  scope "/", SoundForgeWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # API routes
  scope "/api", SoundForgeWeb.API do
    pipe_through :api

    post "/spotify/fetch", SpotifyController, :fetch

    post "/download/track", DownloadController, :create
    get "/download/job/:id", DownloadController, :show

    post "/processing/separate", ProcessingController, :create
    get "/processing/job/:id", ProcessingController, :show
    get "/processing/models", ProcessingController, :models

    post "/analysis/analyze", AnalysisController, :create
    get "/analysis/job/:id", AnalysisController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sound_forge, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SoundForgeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
