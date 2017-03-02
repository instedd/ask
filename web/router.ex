defmodule Ask.Router do
  use Ask.Web, :router
  use Coherence.Router
  use Plug.ErrorHandler
  use Sentry.Plug

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Plug.Static, at: "files/", from: "web/static/assets/files/"
    plug Coherence.Authentication.Session, db_model: Ask.User
  end

  pipeline :protected do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Coherence.Authentication.Session, db_model: Ask.User, protected: true
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_flash

    plug Coherence.Authentication.Session, db_model: Ask.User

    #plug Guardian.Plug.VerifyHeader
    #plug Guardian.Plug.LoadResource
  end

  if Mix.env == :dev do
    scope "/dev" do
      pipe_through [:browser]
      forward "/mailbox", Plug.Swoosh.MailboxPreview, [base_path: "/dev/mailbox"]
    end
  end

  scope "/api" , Ask do
    pipe_through :api

    scope "/v1" do
      delete "/sessions", Coherence.SessionController, :api_delete

      get "/timezones", TimezoneController, :timezones
      resources "/projects", ProjectController, except: [:new, :edit] do
        resources "/surveys", SurveyController, except: [:new, :edit] do
          post "/launch", SurveyController, :launch
          post "/stop", SurveyController, :stop
          resources "/respondents", RespondentController, only: [:index]
          resources "/respondent_groups", RespondentGroupController, only: [:index, :create, :update, :delete]
          get "/respondents/stats", RespondentController, :stats, as: :respondents_stats
          get "/respondents/quotas_stats", RespondentController, :quotas_stats, as: :respondents_quotas_stats
          get "/respondents/csv", RespondentController, :csv, as: :respondents_csv
          get "/respondents/disposition_history_csv", RespondentController, :disposition_history_csv, as: :respondents_disposition_history_csv
          get "/respondents/incentives_csv", RespondentController, :incentives_csv, as: :respondents_incentives_csv
        end
        resources "/questionnaires", QuestionnaireController, except: [:new, :edit] do
          get "/export_zip", QuestionnaireController, :export_zip, as: :questionnaires_export_zip
          post "/import_zip", QuestionnaireController, :import_zip, as: :questionnaires_import_zip
        end
        get "/autocomplete_vars", ProjectController, :autocomplete_vars, as: :autocomplete_vars
        get "/autocomplete_primary_language", ProjectController, :autocomplete_primary_language, as: :autocomplete_primary_language
        get "/autocomplete_other_language", ProjectController, :autocomplete_other_language, as: :autocomplete_other_language
        get "/collaborators", ProjectController, :collaborators, as: :collaborators
      end
      resources "/channels", ChannelController, except: [:new, :edit]
      resources "/audios", AudioController, only: [:create, :show]
      resources "/authorizations", OAuthClientController, only: [:index, :delete]
      get "/authorizations/synchronize", OAuthClientController, :synchronize
      get "/accept_invitation", InviteController, :accept_invitation, as: :accept_invitation
      get "/invite", InviteController, :invite, as: :invite
      get "/invite_mail", InviteController, :invite_mail, as: :invite_mail
      get "/invite_show", InviteController, :show, as: :invite_show
      get "/get_invite_by_email_and_project", InviteController, :get_by_email_and_project
      get "/settings", UserController, :settings, as: :settings
      post "/update_settings", UserController, :update_settings, as: :update_settings
    end
  end

  get "/audio/:id", Ask.AudioDeliveryController, :show
  get "/callbacks/:provider", Ask.CallbackController, :callback
  post "/callbacks/:provider", Ask.CallbackController, :callback
  get "/callbacks/:provider/*path", Ask.CallbackController, :callback
  post "/callbacks/:provider/*path", Ask.CallbackController, :callback
  get "/mobile_survey", Ask.MobileSurveyController, :index
  get "/mobile_survey/get_step", Ask.MobileSurveyController, :get_step

  scope "/", Ask do
    pipe_through :browser
    coherence_routes :public

    # add public resources below
    get "/oauth_client/callback", OAuthClientController, :callback
    get "/registrations/confirmation_sent", Coherence.RegistrationController, :confirmation_sent
    get "/registrations/confirmation_expired", Coherence.RegistrationController, :confirmation_expired
    get "/passwords/password_recovery_sent", Coherence.PasswordController, :password_recovery_sent
    get "/*path", PageController, :index
  end
end
