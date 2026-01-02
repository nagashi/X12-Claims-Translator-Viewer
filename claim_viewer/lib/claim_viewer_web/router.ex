defmodule ClaimViewerWeb.Router do
  use ClaimViewerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ClaimViewerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ClaimViewerWeb do
    pipe_through :browser

 # Handles HTTP GET requests to the root URL ("/")
# Calls the home/2 action in PageController
# Used to render the main home page of the application
get "/", PageController, :home

get "/claims/:id", PageController, :show

# Handles HTTP GET requests to "/claim"
# Calls the claim/2 action in PageController
# Intended to display a claim-related page (if implemented)
get "/claim", PageController, :claim


# Handles HTTP POST requests to "/upload"
# Calls the upload/2 action in PageController
# Used for uploading and processing a JSON claim file
post "/upload", PageController, :upload





  end

  # Other scopes may use custom stacks.
  # scope "/api", ClaimViewerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:claim_viewer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ClaimViewerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
