defmodule Ask.Runtime.RespondentGroup do
  alias Ask.{Repo, Respondent, Stats}

  def insert_all_respondents(sample, project, survey, group, local_time) do
    map_respondent = fn phone_number ->
      canonical_number = Respondent.canonicalize_phone_number(phone_number)
      %{phone_number: phone_number, sanitized_phone_number: canonical_number, canonical_phone_number: canonical_number, survey_id: survey.id, respondent_group_id: group.id, inserted_at: local_time, updated_at: local_time, hashed_number: Respondent.hash_phone_number(phone_number, project.salt), disposition: "registered", stats: %Stats{}, user_stopped: false}
    end

    insert_respondents = fn respondents ->
      Repo.insert_all(Respondent, respondents)
    end

    Stream.map(sample, map_respondent)
    # Insert all respondent in the sample in chunks of 1K
    |> Stream.chunk_every(1_000)
    |> Stream.each(insert_respondents)
    |> Stream.run
  end
end
