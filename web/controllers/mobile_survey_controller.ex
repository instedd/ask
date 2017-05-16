defmodule Ask.MobileSurveyController do
  alias Ask.Runtime.{Broker, Reply}
  alias Ask.Respondent
  use Ask.Web, :controller

  def index(conn, %{"respondent_id" => respondent_id, "token" => token}) do
    respondent = Respondent |> Repo.get(respondent_id)
    if !respondent do
      conn
        |> put_status(:not_found)
        |> put_layout({Ask.LayoutView, "mobile_survey.html"})
        |> render("404.html")
    else
      color_style = color_style_for(respondent_id)
      authorize(conn, respondent_id, token, fn ->
        render_index(conn, respondent_id, token, color_style)
      end)
    end
  end

  defp render_index(conn, respondent_id, token, color_style) do
    conn
    |> put_layout({Ask.LayoutView, "mobile_survey.html"})
    |> render("index.html", respondent_id: respondent_id, token: token, color_style: color_style)
  end

  defp color_style_for(respondent_id) do
    (Respondent
      |> Repo.get(respondent_id)
      |> Repo.preload(:questionnaire)).questionnaire.settings["mobile_web_color_style"]
  end

  defp primary_color_for(color_style) do
    case color_style do
      nil ->
        ''
      color_style ->
        color_style["primary_color"]
    end
  end

  def get_step(conn, %{"respondent_id" => respondent_id, "token" => token}) do
    authorize(conn, respondent_id, token, fn ->
      check_cookie(conn, respondent_id, fn conn ->
        sync_step(conn, respondent_id, :answer)
      end)
    end)
  end

  def send_reply(conn, %{"respondent_id" => respondent_id, "token" => token, "value" => value, "step_id" => step_id}) do
    authorize(conn, respondent_id, token, fn ->
      check_cookie(conn, respondent_id, fn conn ->
        sync_step(conn, respondent_id, {:reply_with_step_id, value, step_id})
      end)
    end)
  end

  defp sync_step(conn, respondent_id, value) do
    respondent = Repo.get!(Respondent, respondent_id)
    survey = Repo.preload(respondent, :survey).survey

    {step, progress, error_message} =
      cond do
        survey.state in ["completed", "cancelled"] ->
          questionnaires = Repo.preload(survey, :questionnaires).questionnaires
          questionnaire = Enum.random(questionnaires)
          msg = questionnaire.settings["mobile_web_survey_is_over_message"] || "The survey is over"
          {end_step(msg), end_progress(), nil}
        respondent.state in ["pending", "active", "stalled", "rejected"] ->
          case Broker.sync_step(respondent, value) do
            {:reply, reply} ->
              {first_step(reply), progress(reply), reply.error_message}
            {:end, {:reply, reply}} ->
              {first_step(reply), progress(reply), reply.error_message}
            :end ->
              {end_step(), end_progress(), nil}
          end
        true ->
          {end_step(fetch_survey_already_taken_message(respondent)), end_progress(), nil}
      end

    title = fetch_title(respondent_id)

    json(conn, %{
      step: step,
      progress: progress,
      error_message:
      error_message,
      title: title,
    })
  end

  defp first_step(reply) do
    reply |> Reply.steps() |> hd
  end

  defp progress(reply) do
    if reply.current_step && reply.total_steps && reply.total_steps > 0 do
      100 * (reply.current_step / reply.total_steps)
    else
      # If no explicit progress is set in the reply, assume we are at the end.
      # This happens in the "thank you" and "quota completed" messages.
      100.0
    end
  end

  defp end_step(msg \\ "The survey has ended") do
    %{
      type: "end",
      prompts: [msg],
      title: msg,
    }
  end

  defp end_progress do
    100.0
  end

  defp fetch_title(respondent_id) do
    respondent = Repo.get!(Respondent, respondent_id)
    questionnaire = Repo.preload(respondent, :questionnaire).questionnaire
    language = respondent.language || questionnaire.default_language
    (questionnaire.settings["title"] || %{})[language] || ""
  end

  defp fetch_survey_already_taken_message(respondent) do
    questionnaire = Repo.preload(respondent, :questionnaire).questionnaire
    language = respondent.language || questionnaire.default_language
    (questionnaire.settings["survey_already_taken_message"] || %{})[language] || "You already took this survey"
  end

  defp authorize(conn, respondent_id, token, success_fn) do
    if Respondent.token(respondent_id) == token do
      success_fn.()
    else
      respondent = Respondent |> Repo.get(respondent_id)
      color_style = color_style_for(respondent_id)

      primary_color = primary_color_for(color_style)

      conn
        |> put_status(403)
        |> put_layout({Ask.LayoutView, "mobile_survey.html"})
        |> render("unauthorized.html", header_color: primary_color)
    end
  end

  defp check_cookie(conn, respondent_id, success_fn) do
    respondent = Repo.get!(Respondent, respondent_id)
    cookie_name = Respondent.mobile_web_cookie_name(respondent_id)
    respondent_cookie = respondent.mobile_web_cookie_code
    if respondent_cookie do
      request_cookie = fetch_cookies(conn).req_cookies[cookie_name]
      if request_cookie == respondent_cookie do
        success_fn.(conn)
      else
        raise Ask.UnauthorizedError, conn: conn
      end
    else
      cookie_value = Ecto.UUID.generate

      respondent
      |> Respondent.changeset(%{mobile_web_cookie_code: cookie_value})
      |> Repo.update!

      conn = conn
      |> put_resp_cookie(cookie_name, cookie_value)

      success_fn.(conn)
    end
  end

  def unauthorized_error(conn, %{"id" => respondent_id}) do
    color_style = color_style_for(respondent_id)
    primary_color = primary_color_for(color_style)
    conn
      |> put_status(401)
      |> put_layout({Ask.LayoutView, "mobile_survey.html"})
      |> render("unauthorized.html", header_color: primary_color)
  end
end
