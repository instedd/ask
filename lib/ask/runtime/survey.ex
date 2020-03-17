defmodule Ask.Runtime.Survey do
  use Timex
  alias Ask.{Repo, Respondent, Logger, SystemTime}
  alias Ask.Runtime.{Session, Reply, Flow, RetriesHistogram}

  def sync_step(respondent, reply, mode \\ nil, now \\ SystemTime.time.now) do
    session = respondent.session |> Session.load
    session_mode = Ask.Runtime.Respondent.session_mode(respondent, session, mode)
    next_action = sync_step_internal(session, reply, session_mode, now)
    handle_next_action(next_action, respondent.id)
  end

  # We expose this method so we can test that if a stale respondent is
  # passed, it's reloaded and the action is retried (this can happen
  # if a timeout happens in between this call)
  def sync_step_internal(session, reply) do
    sync_step_internal(session, reply, session.current_mode, SystemTime.time.now)
  end

  def mask_phone_number(%Respondent{} = respondent, {:reply, response}) do
    pii = respondent.canonical_phone_number |> String.slice(-6..-1)
    # pii can be empty if the sanitized_phone_number has less than 5 digits,
    # that could be mostly to the case of a randomly generated phone number form a test
    # String.contains? returns true for empty strings
    masked_response = if String.length(pii) != 0 && contains_phone_number(response, pii) do
      mask_phone_number(response, phone_number_matcher(pii), pii)
    else
      response
    end

    Flow.Message.reply(masked_response)
  end
  def mask_phone_number(_, reply), do: reply
  def mask_phone_number(response, regex, pii) do
    masked_response = response |> String.replace(regex, "\\1#\\3#\\5#\\7#\\9#\\11#\\13")

    if contains_phone_number(masked_response, pii) do
      mask_phone_number(masked_response, regex, pii)
    else
      masked_response
    end
  end

  def handle_session_step({:ok, %{respondent: respondent} = session, reply, timeout}, now) do
    Ask.Runtime.Respondent.update_respondent(respondent, {:ok, session, timeout}, Reply.disposition(reply), now)
    {:reply, reply}
  end

  def handle_session_step({:hangup, session, reply, timeout, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, {:ok, session, timeout}, Reply.disposition(reply), SystemTime.time.now)
    :end
  end

  def handle_session_step({:end, reply, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, :end, Reply.disposition(reply), nil)

    case Reply.steps(reply) do
      [] ->
        :end
      _ ->
        {:end, {:reply, reply}}
    end
  end

  def handle_session_step({:rejected, reply, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, :rejected)
    {:end, {:reply, reply}}
  end

  def handle_session_step({:rejected, %{respondent: respondent} = session, reply, timeout}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, {:rejected, session, timeout})
    {:reply, reply}
  end

  def handle_session_step({:rejected, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, :rejected)
    :end
  end

  def handle_session_step({:stalled, session, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, {:stalled, session})
  end

  def handle_session_step({:stopped, reply, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, :stopped, Reply.disposition(reply), nil)
    :end
  end

  def handle_session_step({:failed, respondent}, _) do
    Ask.Runtime.Respondent.update_respondent(respondent, :failed)
    :end
  end

  defp sync_step_internal(_, _, :invalid_mode, _) do
    :end
  end

  defp sync_step_internal(session, reply, session_mode, now) do
    transaction_result = Repo.transaction(fn ->
      try do
        reply = mask_phone_number(session.respondent, reply)
        session_step = Session.sync_step(session, reply, session_mode)
        handle_session_step(session_step, now)
      rescue
        e in Ecto.StaleEntryError ->
          Logger.error(e, "Error on sync step internal. Rolling back transaction")
          Repo.rollback(e)
        e ->
          # If we uncomment this a test will fail (the one that cheks that nothing breaks),
          # but this could help you find a bug in a particular test that is not working.
          # if Mix.env == :test do
          #   IO.inspect e
          #   IO.inspect System.stacktrace()
          #   raise e
          # end
          respondent = Repo.get(Respondent, session.respondent.id)
          Logger.error(e, "Error occurred while processing sync step (survey_id: #{respondent.survey_id}, respondent_id: #{respondent.id})")
          Sentry.capture_exception(e, [
            stacktrace: System.stacktrace(),
            extra: %{survey_id: respondent.survey_id, respondent_id: respondent.id}])

          try do
            handle_session_step({:failed, respondent}, now)
          rescue
            e ->
              if Mix.env == :test do
                IO.inspect e
                IO.inspect System.stacktrace()
                raise e
              end
              :end
          end
      end
    end)

    case transaction_result do
      {:ok, response} ->
        response
      {:error, %Ecto.StaleEntryError{}} ->
        respondent = Repo.get(Respondent, session.respondent.id)
        # Maybe timeout or another action was executed while sync_step was executed, so we need to retry
        sync_step(respondent, reply, session_mode)
      value ->
        value
    end
  end

  defp contains_phone_number(response, pii) do
    String.contains?(Respondent.canonicalize_phone_number(response), pii)
  end

  defp phone_number_matcher(pii) do
    String.graphemes(pii)
    |> Enum.reduce("(.*)", fn(digit, regex) ->
      "#{regex}(#{digit})(.*)"
    end)
    |> Regex.compile!
  end

  defp handle_next_action(next_action, respondent_id) do
    respondent = Repo.get(Respondent, respondent_id)
    session = if respondent.session, do: Session.load(respondent.session), else: respondent.session
    RetriesHistogram.next_step(respondent, session, next_action)
    next_action
  end
end
