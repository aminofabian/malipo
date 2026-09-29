defmodule MalipoWeb.Router do
  use MalipoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MalipoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MalipoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MalipoWeb.Plugs.AdminBasicAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :internal do
    plug :accepts, ["json"]
    plug MalipoWeb.Plugs.ServiceAuth
  end

  pipeline :merchant_api do
    plug :accepts, ["json"]
    plug MalipoWeb.Plugs.ApiKeyAuth
  end

  pipeline :public_api do
    plug :accepts, ["json"]
    plug MalipoWeb.Plugs.Cors
  end

  scope "/", MalipoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Deploy probes — no auth.
  scope "/", MalipoWeb do
    get "/health", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/admin", MalipoWeb do
    pipe_through :admin

    live "/", Admin.IntentsLive, :index
    live "/intents", Admin.IntentsLive, :index
    live "/till", Admin.TillLive, :index
    live "/outbox", Admin.OutboxLive, :index
    live "/merchants", Admin.MerchantsLive, :index
    live "/fees", Admin.FeesLive, :index
    live "/daraja/platform", Admin.DarajaPlatformLive, :index
  end

  # Safaricom-facing callbacks — no CSRF, always 200 after persist.
  scope "/webhooks/daraja", MalipoWeb.Webhook do
    pipe_through :api

    post "/stk", DarajaController, :stk
    post "/c2b/validation", DarajaController, :c2b_validation
    post "/c2b/confirmation", DarajaController, :c2b_confirmation
    post "/b2b/result", DarajaController, :b2b_result
    post "/b2b/timeout", DarajaController, :b2b_timeout
  end

  # Java → Malipo (§7.2) + Connect provisioning
  scope "/internal/v1", MalipoWeb do
    pipe_through :internal

    post "/intents", IntentController, :create
    get "/intents/:id", IntentController, :show
    post "/intents/:id/resend", IntentController, :resend
    post "/till-awaits", TillAwaitController, :create

    post "/connect/register", ConnectAuthController, :register
    post "/connect/login", ConnectAuthController, :login

    get "/merchants/:business_id", MerchantController, :show
    get "/merchants/:business_id/payments", MerchantController, :payments
    put "/merchants/:business_id/destination", MerchantController, :put_destination
    post "/merchants/:business_id/confirm", MerchantController, :confirm
    post "/merchants/:business_id/keys", MerchantController, :provision_keys
    put "/merchants/:business_id/webhook", MerchantController, :put_webhook
  end

  # Public read-only fees (marketing + clients) — CORS, no auth.
  scope "/v1", MalipoWeb do
    pipe_through :public_api

    get "/fees", FeeController, :show
    options "/fees", FeeController, :preflight
    get "/fees/quote", FeeController, :quote
    options "/fees/quote", FeeController, :preflight
  end

  # Public merchant API (Malipo Connect keys)
  scope "/v1", MalipoWeb do
    pipe_through :merchant_api

    post "/payments", PaymentController, :create
    get "/payments/:id", PaymentController, :show
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:malipo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MalipoWeb.Telemetry
    end
  end
end
