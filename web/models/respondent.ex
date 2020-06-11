defmodule Ask.Respondent do
  use Ask.Web, :model
  alias Ask.Ecto.Type.JSON
  alias Ask.{Stats, Repo, Respondent, Survey}

  schema "respondents" do
    field :phone_number, :string # phone_number as-it-is in the respondents_list
    field :sanitized_phone_number, :string # phone_number with the channel's patterns applied `channel.apply_patterns(canonical_phone_number)`
    field :canonical_phone_number, :string # phone_number with the basic prunes/validations applied
    field :hashed_number, :string
    field :section_order, JSON

    # Valid states are:
    # * pending: the initial state of a respondent, before communication starts
    # * active: a communication is being held with the respondent
    # * completed: the communication finished succesfully (it reached the end)
    # * failed: communication couldn't be established or was cut, only for IVR
    # * rejected: communication ended because the respondent fell in a full quota bucket
    # * cancelled: when the survey is stopped and has "terminated" state, all the active
    #     respondents will be updated with this state.
    field :state, :string, default: "pending"

    # Valid dispositions are:
    # https://cloud.githubusercontent.com/assets/22697/25618659/3126839e-2f1e-11e7-8a3a-7908f8cd1749.png
    # - registered: just created
    # - queued: call queued / SMS queued to be sent
    # - contacted: call answered (or no_answer reply from Verboice) / SMS delivery confirmed
    # - failed: call was never answered / SMS was never sent => the channel was broken or the number doesn't exist
    # - unresponsive: after contacted, when no more retries are available
    # - started: after the first answered question
    # - ineligible: through flag step, only from started, not partial nor completed
    # - rejected: quota completed
    # - breakoff: stopped responding with no more retries, only from started
    # - refused: respondent refused to take the survey, only from started
    # - partial: through flag step, from started
    # - completed: through flag step from started or partial / survey finished with the respondent on started or partial disposition
    field :disposition, :string, default: "registered"

    field :completed_at, Timex.Ecto.DateTime # only when state=="pending"
    field :timeout_at, Timex.Ecto.DateTime
    field :session, JSON
    field :mode, JSON
    field :effective_modes, JSON
    field :mobile_web_cookie_code, :string
    field :language, :string
    belongs_to :questionnaire, Ask.Questionnaire
    belongs_to :survey, Ask.Survey
    belongs_to :respondent_group, Ask.RespondentGroup
    belongs_to :quota_bucket, Ask.QuotaBucket
    belongs_to :retry_stat, Ask.RetryStat
    has_many :responses, Ask.Response
    has_many :survey_log_entries, Ask.SurveyLogEntry
    field :lock_version, :integer, default: 1
    field :stats, Ask.Stats, default: %Ask.Stats{}
    field :experiment_name, :string, virtual: true
    field :user_stopped, :boolean, default: false

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:phone_number, :sanitized_phone_number, :canonical_phone_number, :state, :session, :quota_bucket_id, :completed_at, :timeout_at, :questionnaire_id, :mode, :disposition, :mobile_web_cookie_code, :language, :effective_modes, :stats, :section_order, :retry_stat_id, :user_stopped])
    |> validate_required([:phone_number, :state, :user_stopped])
    |> validate_inclusion(:disposition, ["registered", "queued", "contacted", "failed", "unresponsive", "started", "ineligible", "rejected", "breakoff", "refused", "partial", "interim partial", "completed"])
    |> validate_inclusion(:state, ["pending", "active", "completed", "failed", "rejected", "cancelled"])
    |> Ecto.Changeset.optimistic_lock(:lock_version)
  end

  def canonicalize_phone_number(text) do
    ~r/[^\d]/ |> Regex.replace(text, "")
  end

  def hash_phone_number(phone_number, salt) do
    "r" <> (String.slice(:crypto.hash(:md5, salt <> phone_number) |> Base.encode16(case: :lower), -12, 12))
  end

  def mask_phone_number(phone_number) do
    Enum.join([replace_numbers_by_hash(String.slice(phone_number, 0..-5)), String.slice(phone_number, -4, 4)], "")
  end

  def replace_numbers_by_hash(string) do
    Regex.replace(~r/[0-9]/, string, "#")
  end

  def show_disposition(disposition) do
    (disposition || "") |> String.capitalize
  end

  def show_section_order(%{section_order: nil}, _), do: ""

  def show_section_order(%{section_order: section_order, questionnaire_id: questionnaire_id}, questionnaires) do
    questionnaire = questionnaires |> Enum.find(fn q -> q.id == questionnaire_id end)
    Enum.map(section_order, fn i -> questionnaire.steps |> Enum.at(i) |> show_section_title(i) end) |> Enum.join(", ")
  end

  defp show_section_title(%{"title" => nil}, index) do
    "Untitled #{index + 1}"
  end

  defp show_section_title(%{"title" => ""}, index) do
    "Untitled #{index + 1}"
  end

  defp show_section_title(%{"title" => title}, _) do
    title
  end

  def token(respondent_id)do
    String.slice(:crypto.hash(:md5, Application.get_env(:ask, Ask.Endpoint)[:secret_key_base] <> "#{respondent_id}") |> Base.encode16(case: :lower), -12, 12)
  end

  def mobile_web_cookie_name(respondent_id) do
    "mobile_web_code_#{respondent_id}"
  end

  def completed_dispositions(_count_partial_results = false), do: ["completed"]

  def completed_dispositions(_count_partial_results = true), do: ["completed", "partial", "interim partial"]

  def final_dispositions do
    ["failed", "unresponsive", "ineligible", "rejected", "breakoff", "refused", "partial", "completed"]
  end

  def non_final_dispositions do
    ["registered", "queued", "contacted", "started", "interim partial"]
  end

  def add_mode_attempt!(respondent, mode), do: respondent |> changeset(%{stats: Stats.add_attempt(respondent.stats, mode)}) |> Repo.update!

  def call_attempted(%{stats: %{pending_call: false} } = respondent), do: respondent
  def call_attempted(%{stats: stats} = respondent), do: respondent |> changeset(%{stats: Stats.with_last_call_attempted(stats)}) |> Repo.update!

  @doc """
  Computes the date-time on which the respondent should be retried given the timeout and time-window availability
  """
  def next_actual_timeout(%Respondent{} = respondent, timeout, now, persist \\ true) do
    timeout_at = next_timeout_lowerbound(timeout, now)
    respondent
    |> survey(persist)
    |> Survey.next_available_date_time(timeout_at)
  end

  defp survey(respondent, persist) do
    if(persist) do
      (respondent |> Repo.preload(:survey)).survey
    else
      respondent.survey
    end
  end

  @doc """
  Computes the date-time on which the respondent would be retried , ignoring their survey's inactivity windows (ie, if it Schedule was to always run)
  """
  def next_timeout_lowerbound(timeout, now), do:
    Timex.shift(now, minutes: timeout)

  @doc """
  This function uses Mutex. Its locks aren't reentrant
  Avoid nesting locks to prevent deadlocks
  """
  def with_lock(respondent_id, operation, respondent_modifier \\ fn x -> x end) do
    Mutex.under(Ask.Mutex, respondent_id, fn ->
      respondent = Respondent
                   |> Repo.get(respondent_id)
                   |> respondent_modifier.()
      operation.(respondent)
    end)
  end

  def update(respondent, changes, persist) do
    if(persist) do
      respondent
      |> Respondent.changeset(changes)
      |> Repo.update!
    else
      Map.merge(respondent, changes)
    end
  end
end
