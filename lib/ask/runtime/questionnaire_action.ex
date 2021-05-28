defmodule Ask.Runtime.QuestionnaireAction do
  alias Ask.Runtime.QuestionnaireExport

  def export_and_zip(questionnaire) do
    QuestionnaireExport.export(questionnaire)
    |> QuestionnaireExport.collect_audios()
    |> QuestionnaireExport.zip_export()
  end
end

defmodule Ask.Runtime.QuestionnaireExport do
  alias Ask.{Questionnaire, Repo, Audio}
  alias Ask.Runtime.CleanI18n

  def export(questionnaire) do
    questionnaire = clean_i18n_quiz(questionnaire)
    audio_ids = collect_audio_ids(questionnaire)

    manifest = %{
      name: questionnaire.name,
      modes: questionnaire.modes,
      steps: questionnaire.steps,
      quota_completed_steps: questionnaire.quota_completed_steps,
      settings: questionnaire.settings,
      partial_relevant_config: questionnaire.partial_relevant_config,
      languages: questionnaire.languages,
      default_language: questionnaire.default_language
    }

    %{
      manifest: manifest,
      audio_ids: audio_ids
    }
  end

  defp collect_audio_ids(questionnaire) do
    all_questionnaire_steps = Questionnaire.all_steps(questionnaire)
    audio_ids = collect_steps_audio_ids(all_questionnaire_steps, [])
    collect_settings_audio_ids(questionnaire.settings, audio_ids)
  end

  def collect_audios(%{
        manifest: manifest,
        audio_ids: audio_ids
      }) do
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

    %{
      manifest: Map.put(manifest, :audio_files, audio_files),
      audio_entries: audio_entries
    }
  end

  def zip_export(%{
        manifest: manifest,
        audio_entries: audio_entries
      }) do
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
    clean = fn quiz, key, path ->
      elem = Map.get(quiz, key)
      clean_elem = CleanI18n.clean(elem, quiz.languages, path)
      Map.put(quiz, key, clean_elem)
    end

    quiz
    # Clean settings
    |> clean.(:settings, ".error_message")
    |> clean.(:settings, ".thank_you_message")
    |> clean.(:steps, ".[].prompt")
    |> clean.(:steps, ".[].choices.[].responses.[]")
    |> clean.(:steps, ".[].refusal.responses")
    # Clean steps inside sections
    |> clean.(:steps, ".[].steps.[].prompt")
    |> clean.(:steps, ".[].steps.[].choices.[].responses.[]")
    |> clean.(:steps, ".[].steps.[].refusal.responses")
    # Clean quota completed steps
    |> clean.(:quota_completed_steps, ".[].prompt")
    |> clean.(:quota_completed_steps, ".[].choices.[].responses.[]")
    |> clean.(:quota_completed_steps, ".[].refusal.responses")
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

#
defmodule Ask.Runtime.CleanI18n do
  @moduledoc """
  When a language is deleted, its associated settings are still there, but they aren't visible to
  the end-user. After exporting and importing the questionnaire, the end-user doesn't expect these
  settings to be still there.
  This module helps cleaning the questionnaire from the setting related to the deleted languages.
  The cleaning is done in memory before exporting it, so it doesn't affect the real questionnaire.
  The path syntax is inspired by [JQ](https://stedolan.github.io/jq/)
  """

  def clean(nil, _filter_languages, _path), do: nil

  def clean(entity, filter_languages, path) do
    forward_path = fn positions -> String.slice(path, positions..-1) end

    cond do
      path == ".prompt" and language_selection_step?(entity) ->
        # Don't clean the language selection step
        entity

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

  defp language_selection_step?(%{"type" => "language-selection"} = _entity), do: true
  defp language_selection_step?(_entity), do: false

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

  defp clean_base_case(entity, _langs), do: entity
end
