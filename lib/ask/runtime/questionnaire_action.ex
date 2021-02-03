defmodule Ask.Runtime.QuestionnaireAction do
  alias Ask.Runtime.QuestionnaireExport

  def export(questionnaire) do
    QuestionnaireExport.export(questionnaire)
  end
end

defmodule Ask.Runtime.QuestionnaireExport do
  alias Ask.{Questionnaire, Repo, Audio}
  alias Ask.Runtime.CleanI18n

  def export(questionnaire) do
    questionnaire = clean_i18n_quiz(questionnaire)
    all_questionnaire_steps = Questionnaire.all_steps(questionnaire)
    audio_ids = collect_steps_audio_ids(all_questionnaire_steps, [])
    audio_ids = collect_settings_audio_ids(questionnaire.settings, audio_ids)
    # for each audio: charges it in memory and then streams it.
    audio_resource =
      Stream.resource(
        fn -> audio_ids end,
        fn audio_ids ->
          case audio_ids do
            [id | tail] ->
              audio = Repo.get_by(Audio, uuid: id)
              {[audio], tail}

            [] ->
              {:halt, audio_ids}
          end
        end,
        fn _ -> [] end
      )

    # The audio file import is based on this list
    # If it's empty, nothing will be imported
    audio_files =
      Stream.map(audio_resource, fn audio ->
        %{
          "uuid" => audio.uuid,
          "original_filename" => audio.filename,
          "source" => audio.source
        }
      end)

    audio_entries =
      Stream.map(audio_resource, fn audio ->
        # Zstream needs to recieve audio.data as enumerable in order to work, otherwise it throws Protocol.undefined error.
        Zstream.entry("audios/" <> Audio.exported_audio_file_name(audio.uuid), [audio.data])
      end)

    manifest = %{
      name: questionnaire.name,
      modes: questionnaire.modes,
      steps: questionnaire.steps,
      quota_completed_steps: questionnaire.quota_completed_steps,
      settings: questionnaire.settings,
      partial_relevant_config: questionnaire.partial_relevant_config,
      languages: questionnaire.languages,
      default_language: questionnaire.default_language,
      audio_files: audio_files
    }

    {:ok, json} = Poison.encode(manifest)

    json_entry =
      Stream.map([json], fn json ->
        Zstream.entry("manifest.json", [json])
      end)

    zip_entries = Stream.concat(audio_entries, json_entry)
    # since audio binary data is created as list for Zstream
    # flatten is needed to allow the data to be sent in chunks
    # otherwise the connection sends the whole list as a chunk
    # and times out.
    Zstream.zip(zip_entries)
    |> Stream.flat_map(fn element ->
      case is_list(element) do
        true -> List.flatten(element)
        false -> element
      end
    end)
  end

  def clean_i18n_quiz(quiz) do
    clean_i18n_fields = Map.keys(quiz)

    Enum.reduce(clean_i18n_fields, quiz, fn field, quiz_acc ->
      clean_i18n_quiz(quiz_acc, field)
    end)
  end

  defp clean_i18n_quiz(quiz, :settings = _field) do
    paths = [
      ".error_message",
      ".thank_you_message"
    ]

    clean_i18n_quiz(quiz, :settings, paths)
  end

  defp clean_i18n_quiz(quiz, key) when key in [:steps, :quota_completed_steps] do
    paths = [
      ".[].prompt",
      ".[].choices.[].responses.[]",
      ".[].refusal.responses"
    ]

    clean_i18n_quiz(quiz, key, paths)
  end

  defp clean_i18n_quiz(quiz, _field) do
    quiz
  end

  defp clean_i18n_quiz(quiz, key, paths) do
    elem = Map.get(quiz, key)

    clean_elem =
      Enum.reduce(paths, elem, fn path, elem_acc ->
        CleanI18n.clean(elem_acc, quiz.languages, path)
      end)

    Map.put(quiz, key, clean_elem)
  end

  defp collect_settings_audio_ids(settings, audio_ids) do
    audio_ids = collect_setting_audio_id(settings["error_message"], audio_ids)
    collect_setting_audio_id(settings["thank_you_message"], audio_ids)
  end

  defp collect_setting_audio_id(nil = _setting, audio_ids) do
    audio_ids
  end

  defp collect_setting_audio_id(setting, audio_ids) do
    collect_lang_prompt_audio_ids(setting, audio_ids)
  end

  defp collect_steps_audio_ids(nil, audio_ids) do
    audio_ids
  end

  defp collect_steps_audio_ids(steps, audio_ids) do
    steps
    |> Enum.reduce(audio_ids, fn step, audio_ids ->
      collect_step_audio_ids(step, audio_ids)
    end)
  end

  defp collect_step_audio_ids(
         %{"prompt" => %{"ivr" => %{"audio_id" => _audio_id}} = prompt},
         audio_ids
       ) do
    collect_prompt_audio_ids(prompt, audio_ids)
  end

  defp collect_step_audio_ids(%{"prompt" => prompt}, audio_ids) do
    collect_lang_prompt_audio_ids(prompt, audio_ids)
  end

  defp collect_step_audio_ids(_, audio_ids) do
    audio_ids
  end

  defp collect_lang_prompt_audio_ids(prompt, audio_ids) do
    prompt
    |> Enum.reduce(audio_ids, fn {_lang, lang_prompt}, audio_ids ->
      collect_prompt_audio_ids(lang_prompt, audio_ids)
    end)
  end

  defp collect_prompt_audio_ids(%{"ivr" => %{"audio_id" => audio_id} = _prompt}, audio_ids) do
    [audio_id | audio_ids]
  end

  defp collect_prompt_audio_ids(_, audio_ids) do
    audio_ids
  end
end

# The path syntax is inspired by [JQ](https://stedolan.github.io/jq/)
defmodule Ask.Runtime.CleanI18n do
  def clean(nil, _filter_languages, _path), do: nil

  def clean(entity, filter_languages, path) do
    forward_path = fn positions -> String.slice(path, positions..-1) end
    cond do
      # Base case
      path == "" ->
        clean_base_case(entity, filter_languages)
      # Clean every map element
      String.starts_with?(path, ".[]") and is_map(entity) ->
        clean_map(entity, filter_languages, forward_path.(3))
      # Clean every list element
      String.starts_with?(path, ".[]") and is_list(entity) ->
        clean_list(entity, filter_languages, forward_path.(3))
      # Clean the requested key of a map
      !!path and is_map(entity) ->
        clean_key(entity, filter_languages, path, forward_path)
      true ->
        {:error, "Invalid path"}
    end
  end

  defp clean_key(entity, langs, path, forward_path) do
    key = String.split(path, ".") |> Enum.at(1)
    path = forward_path.(String.length(key) + 1)
    clean_map(entity, langs, path, key)
  end

  defp clean_list(entity, langs, path) do
    Enum.map(entity, fn elem ->
      clean(elem, langs, path)
    end)
  end

  defp clean_map(entity, langs, path, filter_key \\ nil) do
    clean_entity_key = fn entity, key ->
      elem = Map.get(entity, key)
      if filter_key == nil or filter_key == key do
        clean(elem, langs, path)
      else
        elem
      end
    end

    Enum.reduce(Map.keys(entity), entity, fn key, entity_acc ->
      Map.put(entity_acc, key, clean_entity_key.(entity, key))
    end)
  end

  defp clean_base_case(entity, langs) when is_map(entity) do
    entity_languages = Map.keys(entity)

    deleted_langs =
      Enum.filter(entity_languages, fn lang ->
        lang not in langs
      end)

    Enum.reduce(deleted_langs, entity, fn lang, entity_acc ->
      Map.delete(entity_acc, lang)
    end)
  end
end
