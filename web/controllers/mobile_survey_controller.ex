defmodule Ask.MobileSurveyController do
  alias Ask.Runtime.{Broker, Reply}
  alias Ask.Respondent
  use Ask.Web, :controller

  def index(conn, %{"respondent_id" => respondent_id, "token" => token}) do
    if Respondent.token(respondent_id) == token do
      conn
      |> put_layout({Ask.LayoutView, "mobile_survey.html"})
      |> render("index.html", respondent_id: respondent_id)
    else
      raise Ask.UnauthorizedError, conn: conn
    end
  end

  def get_step(conn, %{"respondent_id" => respondent_id}) do
    sync_step(conn, respondent_id, :answer)
  end

  def send_reply(conn, %{"respondent_id" => respondent_id, "value" => value}) do
    sync_step(conn, respondent_id, {:reply, value})
  end

  defp sync_step(conn, respondent_id, value) do
    respondent = Repo.get!(Respondent, respondent_id)

    step =
      if respondent.state in ["pending", "active", "stalled"] do
        case Broker.sync_step(respondent, value) do
          {:reply, reply} ->
            reply |> Reply.steps() |> hd
          {:end, {:reply, reply}} ->
            reply |> Reply.steps() |> hd
          :end ->
            end_step()
        end
      else
        end_step()
      end

    render(conn, "show_step.json", step: step)
  end

  defp end_step do
    %{
      type: "explanation",
      prompts: ["The survey has ended"],
      title: "The survey has ended",
    }
  end
end
