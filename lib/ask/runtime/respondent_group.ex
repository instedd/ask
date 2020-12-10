defmodule Ask.Runtime.RespondentGroup do
  alias Ask.{Survey, Repo, Respondent, Stats, RespondentGroup}
  alias Ecto.Changeset

  def create(name, phone_numbers, survey) do
    sample = phone_numbers |> Enum.take(5)
    respondents_count = phone_numbers |> length

    respondent_group =
      %RespondentGroup{
        name: name,
        survey_id: survey.id,
        sample: sample,
        respondents_count: respondents_count
      }
      |> Repo.insert!()
      |> Repo.preload(:respondent_group_channels)

    insert_respondents(phone_numbers, respondent_group)

    survey
    |> Repo.preload([:questionnaires])
    |> Repo.preload([:quota_buckets])
    |> Repo.preload(respondent_groups: [respondent_group_channels: :channel])
    |> Changeset.change()
    |> Survey.update_state()
    |> Repo.update!()

    respondent_group
  end

  def insert_respondents(phone_numbers, respondent_group) do
    respondent_group = Repo.preload(respondent_group, survey: :project)

    map_respondent = fn phone_number ->
      canonical_number = Respondent.canonicalize_phone_number(phone_number)

      %{
        phone_number: phone_number,
        sanitized_phone_number: canonical_number,
        canonical_phone_number: canonical_number,
        survey_id: respondent_group.survey_id,
        respondent_group_id: respondent_group.id,
        hashed_number:
          Respondent.hash_phone_number(phone_number, respondent_group.survey.project.salt),
        disposition: "registered",
        stats: %Stats{},
        user_stopped: false,
        inserted_at: Timex.now(),
        updated_at: Timex.now()
      }
    end

    insert_respondents = fn respondents ->
      Repo.insert_all(Respondent, respondents)
    end

    Stream.map(phone_numbers, map_respondent)
    # Insert all respondent in the sample in chunks of 1K
    |> Stream.chunk_every(1_000)
    |> Stream.each(insert_respondents)
    |> Stream.run()
  end
end
