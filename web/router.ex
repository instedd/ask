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
    plug :accepts, ["json", "json-api"]
    plug :fetch_session
    plug :fetch_flash

    plug Coherence.Authentication.Session, db_model: Ask.User

    #plug Guardian.Plug.VerifyHeader
    #plug Guardian.Plug.LoadResource
  end

  pipeline :csv_json_api do
    plug :accepts, ["json", "csv"]
    plug :fetch_session
    plug :fetch_flash

    plug Coherence.Authentication.Session, db_model: Ask.User
  end

  pipeline :csv_api do
    plug :accepts, ["csv"]
    plug :fetch_session
    plug :fetch_flash

    plug Coherence.Authentication.Session, db_model: Ask.User
  end

  pipeline :mp3_api do
    plug TrailingFormatPlug
    plug :accepts, ["mp3"]
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
        resources "/folders", FolderController, only: [:create, :index, :delete] do
          post "/set_name", FolderController, :set_name
          resources "/surveys", SurveyController, only: [:create]
        end
        delete "/memberships/remove", MembershipController, :remove, as: :membership_remove
        put "/memberships/update", MembershipController, :update, as: :membership_update
        resources "/channels", ChannelController, only: [:index]
        resources "/surveys", SurveyController, except: [:new, :edit] do
          post "/set_name", SurveyController, :set_name
          post "/set_folder_id", SurveyController, :set_folder_id
          post "/set_description", SurveyController, :set_description
          post "/launch", SurveyController, :launch
          post "/stop", SurveyController, :stop
          post "/config", SurveyController, :config
          put "/update_locked_status", SurveyController, :update_locked_status, as: :update_locked_status
          get "/config", SurveyController, :config
          get "/stats", SurveyController, :stats
          get "/retries_histograms", SurveyController, :retries_histograms
          resources "/integrations", IntegrationController, only: [:index, :create]
          resources "/respondents", RespondentController, only: [:index]
          resources "/respondent_groups", RespondentGroupController, only: [:index, :create, :update, :delete] do
            post "/add", RespondentGroupController, :add, as: :add
            post "/replace", RespondentGroupController, :replace, as: :replace
          end
          get "/respondents/stats", RespondentController, :stats, as: :respondents_stats
          get "/simulation_status", SurveyController, :simulation_status
          post "/stop_simulation", SurveyController, :stop_simulation
          get "/links/:name", SurveyController, :create_link, as: :links
          put "/links/:name", SurveyController, :refresh_link, as: :links
          delete "/links/:name", SurveyController, :delete_link, as: :links
          scope "/flow-results" do
            get "/packages", FloipController, :index, as: :packages
            get "/packages/:floip_package_id", FloipController, :show, as: :package_descriptor
            get "/packages/:floip_package_id/responses", FloipController, :responses, as: :package_responses
          end
        end
        post "/surveys/simulate_questionanire", SurveyController, :simulate_questionanire
        resources "/questionnaires", QuestionnaireController, except: [:new, :edit] do
          get "/export_zip", QuestionnaireController, :export_zip, as: :questionnaires_export_zip
          post "/import_zip", QuestionnaireController, :import_zip, as: :questionnaires_import_zip
        end
        get "/autocomplete_vars", ProjectController, :autocomplete_vars, as: :autocomplete_vars
        get "/autocomplete_primary_language", ProjectController, :autocomplete_primary_language, as: :autocomplete_primary_language
        get "/autocomplete_other_language", ProjectController, :autocomplete_other_language, as: :autocomplete_other_language
        get "/collaborators", ProjectController, :collaborators, as: :collaborators
        get "/activities", ProjectController, :activities, as: :activities
        post "/leave", ProjectController, :leave, as: :leave
        put "/update_archived_status", ProjectController, :update_archived_status, as: :update_archived_status
      end
      resources "/channels", ChannelController, except: [:new, :edit]
      resources "/audios", AudioController, only: [:create, :show]
      resources "/authorizations", OAuthClientController, only: [:index, :delete]
      get "/authorizations/synchronize", OAuthClientController, :synchronize
      get "/authorizations/ui_token", OAuthClientController, :ui_token
      get "/accept_invitation", InviteController, :accept_invitation, as: :accept_invitation
      get "/invite", InviteController, :invite, as: :invite
      get "/send_invitation", InviteController, :send_invitation, as: :send_invitation
      put "/invite_update", InviteController, :update, as: :invite_update
      delete "/invite_remove", InviteController, :remove, as: :invite_remove
      get "/invite_show", InviteController, :show, as: :invite_show
      get "/get_invite_by_email_and_project", InviteController, :get_by_email_and_project
      get "/settings", UserController, :settings, as: :settings
      post "/update_settings", UserController, :update_settings, as: :update_settings
    end
  end

  scope "/api" , Ask do
    scope "/v1" do
      resources "/projects", ProjectController, only: [] do
        resources "/surveys", SurveyController, only: [] do
          scope "/respondents" do
            pipe_through :csv_json_api
            get "/results", RespondentController, :results, as: :respondents_results
          end
          scope "/respondents" do
            pipe_through :csv_api
            get "/disposition_history", RespondentController, :disposition_history, as: :respondents_disposition_history
            get "/incentives", RespondentController, :incentives, as: :respondents_incentives
            get "/interactions", RespondentController, :interactions, as: :respondents_interactions
          end
        end
      end
    end
  end

  scope "/audio" do
    pipe_through :mp3_api
    get "/:id", Ask.AudioDeliveryController, :show
  end

  get "/callbacks/:provider", Ask.CallbackController, :callback
  post "/callbacks/:provider", Ask.CallbackController, :callback
  get "/callbacks/:provider/*path", Ask.CallbackController, :callback
  post "/callbacks/:provider/*path", Ask.CallbackController, :callback
  get "/mobile/:respondent_id", Ask.MobileSurveyController, :index
  get "/mobile/get_step/:respondent_id", Ask.MobileSurveyController, :get_step
  post "/mobile/send_reply/:respondent_id", Ask.MobileSurveyController, :send_reply
  get "/mobile/errors/unauthorized", Ask.MobileSurveyController, :unauthorized_error
  get "/link/:hash", Ask.ShortLinkController, :access

  scope "/", Ask do
    pipe_through :browser
    coherence_routes :all

    # add public resources below
    get "/oauth_client/callback", OAuthClientController, :callback
    get "/registrations/confirmation_sent", Coherence.RegistrationController, :confirmation_sent
    get "/registrations/confirmation_expired", Coherence.RegistrationController, :confirmation_expired
    get "/passwords/password_recovery_sent", Coherence.PasswordController, :password_recovery_sent
    get "/session/oauth_callback", Coherence.SessionController, :oauth_callback
    get "/*path", PageController, :index
  end
end
