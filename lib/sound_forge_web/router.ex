defmodule SoundForgeWeb.Router do
  use SoundForgeWeb, :router

  import SoundForgeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SoundForgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SoundForgeWeb.Plugs.SecurityHeaders
    plug SoundForgeWeb.Plugs.RateLimiter, limit: 120, window_ms: 60_000
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug :accepts, ["json"]
    plug SoundForgeWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000
    plug SoundForgeWeb.Plugs.APIAuth
  end

  scope "/", SoundForgeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/", DashboardLive, :index
    live "/tracks/:id", DashboardLive, :show
    get "/files/*path", FileController, :serve

    # Export routes
    get "/export/stem/:id", ExportController, :download_stem
    get "/export/stems/:track_id", ExportController, :download_all_stems
    get "/export/analysis/:track_id", ExportController, :export_analysis
  end

  # Other scopes may use custom stacks.
  scope "/", SoundForgeWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # API routes (authenticated + rate limited)
  scope "/api", SoundForgeWeb.API do
    pipe_through :api_auth

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

  ## Authentication routes

  scope "/", SoundForgeWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", SoundForgeWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", SoundForgeWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
