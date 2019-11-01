defmodule Ask.Runtime.VerboiceChannel do
  alias __MODULE__
  use Ask.Web, :model
  alias Ask.{Repo, Respondent, Channel, SurvedaMetrics, Stats, RetryStat}
  alias Ask.Runtime.{Broker, Flow, Reply}
  alias Ask.Router.Helpers
  import Plug.Conn
  import XmlBuilder
  @behaviour Ask.Runtime.ChannelProvider
  defstruct [:client, :channel_name, :channel_id]

  def new(channel) do
    channel_name = channel.settings["verboice_channel"]
    channel_id = channel.settings["verboice_channel_id"]
    client = create_client(channel.user_id, channel.base_url)
    %VerboiceChannel{client: client, channel_name: channel_name, channel_id: channel_id}
  end

  def oauth2_authorize(code, redirect_uri, base_url) do
    verboice_config = Ask.Config.provider_config(Verboice, base_url)
    guisso_config = verboice_config[:guisso]

    client = OAuth2.Client.new([
      client_id: guisso_config[:client_id],
      redirect_uri: redirect_uri,
      token_url: "#{guisso_config[:base_url]}/oauth2/token",
    ])

    client = OAuth2.Client.get_token!(client,
      code: code,
      client_secret: guisso_config[:client_secret],
      token_type: "bearer")

    client.token
  end

  def oauth2_refresh(access_token, base_url) do
    verboice_config = Ask.Config.provider_config(Verboice, base_url)
    guisso_config = verboice_config[:guisso]

    client = OAuth2.Client.new([
      token: access_token,
      client_id: guisso_config[:client_id],
      token_url: "#{guisso_config[:base_url]}/oauth2/token",
    ])

    client = OAuth2.Client.refresh_token!(client,
      client_secret: guisso_config[:client_secret])

    client.token
  end

  def gather(respondent, prompts = [prompt, _ | _], num_digits) do
    [say_or_play(prompt) | gather(respondent, tl(prompts), num_digits)]
  end

  def gather(respondent, prompts, num_digits) do
    gather_options = %{action: callback_url(respondent), finishOnKey: ""}
    |> add_num_digits(num_digits)

    [
      # We need to set finishOnKey="" so that when a user presses '#'
      # the current question doesn't give a "timeout" from Verboice,
      # and '#' is sent here so it can be considered a refusal, a valid
      # option, etc.
      element(:Gather, gather_options, [
        say_or_play(prompts)
      ]),
      element(:Redirect, no_reply_callback_url(respondent))
    ]
  end

  defp add_num_digits(options, num_digits) do
    if num_digits do
      Map.put(options, :numDigits, num_digits)
    else
      options
    end
  end

  def say_or_play([prompt]) do
    [say_or_play(prompt)]
  end

  def say_or_play([prompt | prompts]) do
    [say_or_play(prompt) | say_or_play(prompts)]
  end

  def say_or_play(%{"audio_source" => audio_source, "audio_id" => audio_id}) when audio_source in ["upload", "record"] do
    element(:Play, "#{Helpers.audio_delivery_url(Ask.Endpoint, :show, audio_id)}.mp3")
  end

  def say_or_play(%{"audio_source" => "tts", "text" => text}) do
    element(:Say, text)
  end

  defp hangup do
    element(:Hangup)
  end

  defp response(content) when is_list(content) do
    element(:Response, content)
  end

  defp response(content) do
    element(:Response, [content])
  end

  defp create_client(user_id, base_url) do
    oauth_token = Ask.OAuthTokenServer.get_token "verboice", base_url, user_id
    Verboice.Client.new(base_url, oauth_token)
  end

  def sync_channels(user_id, base_url) do
    client = create_client(user_id, base_url)

    case client |> Verboice.Client.get_channels do
      {:ok, channel_names} ->
        sync_channels(user_id, base_url, channel_names)

      _ -> :error
    end
  end

  def sync_channels(user_id, base_url, api_channels) do
    user = Ask.User |> Repo.get!(user_id)
    channels =
      user
      |> assoc(:channels)
      |> where([c], c.provider == "verboice" and c.base_url == ^base_url)
      |> Repo.all()

    channels |> Enum.each(fn channel ->
      exists =
        api_channels
        |> Enum.any?(&match_channel(channel, &1))

      if !exists do
        Ask.Channel.delete(channel)
      end
    end)

    api_channels |> Enum.each(fn api_channel ->
      channel =
        channels
        |> Enum.find(&match_channel(&1, api_channel))

      channel =
        if channel do
          channel
        else
          user
          |> Ecto.build_assoc(:channels)
        end

      channel
      |> channel_changeset(base_url, api_channel)
      |> Repo.insert_or_update!()
    end)
  end

  def create_channel(user, base_url, api_channel) do
    user
    |> Ecto.build_assoc(:channels)
    |> channel_changeset(base_url, api_channel)
    |> Repo.insert!()
  end

  defp channel_changeset(channel, base_url, api_channel) do
    settings = %{
      "verboice_channel" => api_channel["name"],
      "verboice_channel_id" => api_channel["id"]
    }

    settings =
      if api_channel["shared_by"] do
        settings |> Map.put("shared_by", api_channel["shared_by"])
      else
        settings
      end

    Channel.changeset(channel, %{
      name: api_channel["name"],
      type: "ivr",
      provider: "verboice",
      base_url: base_url,
      settings: settings
    })
  end

  defp match_channel(%{settings: %{"verboice_channel_id" => id}}, %{"id" => id}), do: true
  defp match_channel(%{settings: %{"verboice_channel" => name}}, %{"name" => name}), do: true
  defp match_channel(_, _), do: false

  defp channel_failed(respondent, "expired", _) do
    Broker.contact_attempt_expired(respondent)
  end

  defp channel_failed(respondent, "failed", %{"CallStatusReason" => "Busy", "CallStatusCode" => code}) do
    Broker.channel_failed(respondent, "User hangup (#{code})")
  end

  defp channel_failed(respondent, "failed", %{"CallStatusReason" => reason, "CallStatusCode" => code}) do
    Broker.channel_failed(respondent, "#{reason} (#{code})")
  end

  defp channel_failed(respondent, status, %{"CallStatusReason" => reason, "CallStatusCode" => code}) do
    Broker.channel_failed(respondent, "#{status}: #{reason} (#{code})")
  end

  defp channel_failed(respondent, "failed", %{"CallStatusReason" => "Busy"}) do
    Broker.channel_failed(respondent, "User hangup")
  end

  defp channel_failed(respondent, "failed", %{"CallStatusReason" => reason}) do
    Broker.channel_failed(respondent, "#{reason}")
  end

  defp channel_failed(respondent, status, %{"CallStatusReason" => reason}) do
    Broker.channel_failed(respondent, "#{status}: #{reason}")
  end

  defp channel_failed(respondent, "failed", %{"CallStatusCode" => code}) do
    Broker.channel_failed(respondent, "(#{code})")
  end

  defp channel_failed(respondent, status, %{"CallStatusCode" => code}) do
    Broker.channel_failed(respondent, "#{status} (#{code})")
  end

  defp channel_failed(respondent, status, _) do
    Broker.channel_failed(respondent, status)
  end

  def update_call_time_seconds(respondent, call_time) do
    stats = respondent.stats
    |> Stats.total_call_time_seconds(call_time)

    respondent
    |> Respondent.changeset(%{stats: stats})
    |> Repo.update!
  end

  defp set_retry_stat_timeout(%Respondent{timeout_at: timeout_at, survey_id: survey_id, stats: stats, mode: mode}) do
    attempts = stats |> Stats.attempts(:all)
    RetryStat.subtract!(%{attempt: attempts, mode: mode, retry_time: "", survey_id: survey_id})
    RetryStat.add!(%{attempt: attempts, mode: mode, retry_time: Timex.format!(timeout_at, "%Y%0m%0d%H%M", :strftime), survey_id: survey_id})
  end

  def callback(conn, %{"path" => ["status", respondent_id, _token], "CallStatus" => status, "CallDuration" => call_duration_seconds} = params) do
    call_duration = call_duration_seconds |> String.to_integer
    respondent = Repo.get!(Respondent, respondent_id)
    |> update_call_time_seconds(call_duration)
    case status do
      s when s in ["failed", "busy", "no-answer", "expired"] ->
        set_retry_stat_timeout(respondent)

        channel_failed(respondent, status, params)
      _ -> :ok
    end
    SurvedaMetrics.increment_counter_with_label(:surveda_verboice_status_callback, [status])
    conn |> send_resp(200, "")
  end

  def callback(conn, params) do
    callback(conn, params, Broker)
  end

  def callback(conn, params = %{"respondent" => respondent_id}, broker) do
    respondent = Respondent |> Repo.get(respondent_id)

    response_content = case respondent do
      nil ->
        hangup()

      %Respondent{session: %{"current_mode" => %{"mode" => "ivr"}}} ->
        response = case params["Digits"] do
          nil -> Flow.Message.answer()
          "timeout" -> Flow.Message.no_reply()
          digits -> Flow.Message.reply(digits)
        end

        case broker.sync_step(respondent, response, "ivr") do
          {:reply, reply} ->
            prompts = Reply.prompts(reply)
            num_digits = Reply.num_digits(reply)
            gather(respondent, prompts, num_digits)
          {:end, {:reply, reply}} ->
            prompts = Reply.prompts(reply)
            say_or_play(prompts) ++ [hangup()]
          :end ->
            hangup()
        end

      _ ->
        hangup()
    end

    reply = response(response_content) |> generate

    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, reply)
  end

  def callback(conn, _, _) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, response(hangup()) |> generate)
  end

  def callback_url(respondent) do
    Ask.Router.Helpers.callback_url(Ask.Endpoint, :callback, "verboice", respondent: respondent.id)
  end

  def no_reply_callback_url(respondent) do
    Ask.Router.Helpers.callback_url(Ask.Endpoint, :callback, "verboice", respondent: respondent.id, Digits: "timeout")
  end

  def status_callback_url(respondent, token) do
    respondent_id = respondent.id |> Integer.to_string
    Ask.Router.Helpers.callback_url(Ask.Endpoint, :callback, "verboice", ["status", respondent_id, token], [])
  end

  def process_call_response(response) do
    case response do
      {:ok, %{"call_id" => call_id}} ->
        {:ok, %{verboice_call_id: call_id}}
      _ ->
        {:error, response}
    end
  end

  def check_status(
    %{
      "status" => %{
        "ok" => false,
        "messages" => messages
      }
    }
  ), do: {:down, messages}

  def check_status(%{"enabled" => false}), do: {:down, ["Channel is disabled"]}

  def check_status(_), do: :up

  defimpl Ask.Runtime.Channel, for: Ask.Runtime.VerboiceChannel do
    def has_delivery_confirmation?(_), do: false
    def ask(_, _, _, _), do: throw(:not_implemented)
    def prepare(_, _), do: :ok

    def setup(channel, respondent, token, not_before, not_after) do
      params = [
        address: respondent.sanitized_phone_number,
        callback_url: VerboiceChannel.callback_url(respondent),
        status_callback_url: VerboiceChannel.status_callback_url(respondent, token),
        not_before: not_before,
        not_after: not_after
      ]

      params =
        if channel.channel_id do
          Keyword.put(params, :channel_id, channel.channel_id)
        else
          Keyword.put(params, :channel, channel.channel_name)
        end

      channel.client
      |> Verboice.Client.call(params)
      |> Ask.Runtime.VerboiceChannel.process_call_response
    end

    def has_queued_message?(channel, %{"verboice_call_id" => call_id}) do
      response = channel.client
      |> Verboice.Client.call_state(call_id)
      case response do
        {:ok, %{"state" => "completed"}} -> false
        {:ok, %{"state" => "failed"}} -> false
        {:ok, %{"state" => "canceled"}} -> false
        {:ok, %{"state" => _}} -> true
        _ -> false
      end
    end
    def has_queued_message?(_, _) do
      false
    end

    def message_expired?(channel, %{"verboice_call_id" => call_id}) do
      response = channel.client
      |> Verboice.Client.call_state(call_id)
      case response do
        {:ok, %{"state" => "expired"}} -> true
        _ -> false
      end
    end
    def message_expired?(_, _) do
      false
    end

    def cancel_message(channel, %{"verboice_call_id" => call_id}) do
      channel.client
      |> Verboice.Client.cancel(call_id)
    end
    def cancel_message(_, _) do
      :ok
    end

    def check_status(channel) do
      case channel.client |> Verboice.Client.get_channel(channel.channel_id) do
        {:ok, channel} -> VerboiceChannel.check_status(channel)
        error -> error
      end
    end
  end
end
