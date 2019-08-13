defmodule Ask.ActivityLog do
  use Ask.Web, :model
  import User.Helper
  alias Ask.{ActivityLog, Project, Survey, Questionnaire, Folder}

  schema "activity_log" do
    belongs_to :project, Ask.Project
    belongs_to :user, Ask.User
    field :entity_type, :string
    field :entity_id, :integer
    field :action, :string
    field :metadata, Ask.Ecto.Type.JSON
    field :remote_ip, :string

    timestamps()
  end

  def valid_actions("project"), do:
    ["create_invite", "edit_invite", "delete_invite", "edit_collaborator", "remove_collaborator"]

  def valid_actions("survey"), do:
    ["create", "edit", "rename", "change_description", "lock", "unlock", "delete", "start", "stop", "download", "enable_public_link", "regenerate_public_link", "disable_public_link", "change_folder"]

  def valid_actions("questionnaire"), do:
    ["create", "edit", "rename", "delete", "add_mode", "remove_mode", "add_language", "remove_language", "create_step", "delete_step", "rename_step", "edit_step", "edit_settings", "create_section", "rename_section", "delete_section", "edit_section"]

  def valid_actions("folder"), do:
  ["rename"]

  def valid_actions(_), do: []

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:project_id, :user_id, :entity_id, :entity_type, :action, :metadata, :remote_ip])
    |> validate_inclusion(:action, valid_actions(params[:entity_type] || struct.entity_type))
    |> validate_required([:project_id, :entity_id, :entity_type, :action, :remote_ip])
  end

  defp typeof(%Project{}), do: "project"
  defp typeof(%Survey{}), do: "survey"
  defp typeof(%Questionnaire{}), do: "questionnaire"
  defp typeof(%Folder{}), do: "folder"

  defp create(action, project, conn, entity, metadata) do
    user_id = case current_user(conn) do
      nil -> nil
      user -> user.id
    end

    ActivityLog.changeset(%ActivityLog{}, %{
      project_id: project.id,
      user_id: user_id,
      entity_type: typeof(entity),
      entity_id: entity.id,
      remote_ip: :inet_parse.ntoa(conn.remote_ip) |> to_string,
      action: action,
      metadata: metadata
    })
  end

  defp report_type_from(target_name) do
    case target_name do
      "results" -> "survey_results"
      target_name -> target_name
    end
  end

  def edit_collaborator(project, conn, collaborator, old_role, new_role) do
    create("edit_collaborator", project, conn, project, %{project_name: project.name,
      collaborator_email: collaborator.email,
      collaborator_name: collaborator.name,
      old_role: old_role,
      new_role: new_role
    })
  end

  def remove_collaborator(project, conn, collaborator, role) do
    create("remove_collaborator", project, conn, project, %{
      project_name: project.name,
      collaborator_email: collaborator.email,
      collaborator_name: collaborator.name,
      role: role
    })
  end

  def edit_invite(project, conn, target_email, old_role, new_role) do
    create("edit_invite", project, conn, project, %{
      project_name: project.name,
      collaborator_email: target_email,
      old_role: old_role,
      new_role: new_role
    })
  end

  def delete_invite(project, conn, target_email, role) do
    create("delete_invite", project, conn, project, %{
      project_name: project.name,
      collaborator_email: target_email,
      role: role
    })
  end

  def create_invite(project, conn, target_email, role) do
    create("create_invite", project, conn, project, %{
      project_name: project.name,
      collaborator_email: target_email,
      role: role
    })
  end

  def download(project, conn, survey, report_type) do
    create("download", project, conn, survey, %{
      survey_name: survey.name,
      report_type: report_type
    })
  end

  def enable_public_link(project, conn, survey, target_name) do
    create("enable_public_link", project, conn, survey, %{
      survey_name: survey.name,
      report_type: report_type_from(target_name)
    })
  end

  def regenerate_public_link(project, conn, survey, target_name) do
    create("regenerate_public_link", project, conn, survey, %{
      survey_name: survey.name,
      report_type: report_type_from(target_name)
    })
  end

  def disable_public_link(project, conn, survey, link) do
    create("disable_public_link", project, conn, survey, %{
      survey_name: survey.name,
      report_type: report_type_from(link.name |> String.split("/") |> List.last)
    })
  end

  def create_survey(project, conn, survey) do
    create("create", project, conn, survey, nil)
  end

  def edit_survey(project, conn, survey) do
    create("edit", project, conn, survey, %{survey_name: survey.name})
  end

  def rename_survey(project, conn, survey, old_survey_name, new_survey_name) do
    create("rename", project, conn, survey, %{
      old_survey_name: old_survey_name,
      new_survey_name: new_survey_name
    })
  end

  def rename_folder(project, conn, folder, old_folder_name, new_folder_name) do
    create("rename", project, conn, folder, %{
      old_folder_name: old_folder_name,
      new_folder_name: new_folder_name
    })
  end

  def change_folder(project, conn, survey, old_folder_name, new_folder_name) do
    create("change_folder", project, conn, survey, %{
      survey_name: survey.name,
      old_folder_name: old_folder_name,
      new_folder_name: to_string(new_folder_name)
    })
  end

  def change_survey_description(project, conn, survey, old_survey_description, new_survey_description) do
    create("change_description", project, conn, survey, %{
      survey_name: survey.name,
      old_survey_description: old_survey_description,
      new_survey_description: new_survey_description
    })
  end

  def lock_survey(project, conn, survey) do
    create("lock", project, conn, survey, %{
      survey_name: survey.name
    })
  end

  def unlock_survey(project, conn, survey) do
    create("unlock", project, conn, survey, %{
      survey_name: survey.name
    })
  end

  def delete_survey(project, conn, survey) do
    create("delete", project, conn, survey, %{survey_name: survey.name})
  end

  def start(project, conn, survey) do
    create("start", project, conn, survey, %{survey_name: survey.name})
  end

  def stop(project, conn, survey) do
    create("stop", project, conn, survey, %{survey_name: survey.name})
  end

  def create_questionnaire(project, conn, questionnaire) do
    create("create", project, conn, questionnaire, nil)
  end

  def edit_questionnaire(project, conn, questionnaire) do
    create("edit", project, conn, questionnaire, %{questionnaire_name: questionnaire.name})
  end

  def add_questionnaire_mode(project, conn, questionnaire, questionnaire_name, added_mode) do
    create("add_mode", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, mode: added_mode})
  end

  def remove_questionnaire_mode(project, conn, questionnaire, questionnaire_name, removed_mode) do
    create("remove_mode", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, mode: removed_mode})
  end

  def add_questionnaire_language(project, conn, questionnaire, questionnaire_name, added_language) do
    create("add_language", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, language: added_language})
  end

  def remove_questionnaire_language(project, conn, questionnaire, questionnaire_name, removed_language) do
    create("remove_language", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, language: removed_language})
  end

  def create_questionnaire_section(project, conn, questionnaire, questionnaire_name, section_id, section_title) do
    create("create_section", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, section_id: section_id, section_title: section_title})
  end

  def rename_questionnaire_section(project, conn, questionnaire, questionnaire_name, section_id, old_section_title, new_section_title) do
    create("rename_section", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, section_id: section_id, old_section_title: old_section_title, new_section_title: new_section_title})
  end

  def delete_questionnaire_section(project, conn, questionnaire, questionnaire_name, section_id, section_title) do
    create("delete_section", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, section_id: section_id, section_title: section_title})
  end

  def edit_questionnaire_section(project, conn, questionnaire, questionnaire_name, section_id, section_title) do
    create("edit_section", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, section_id: section_id, section_title: section_title})
  end

  def create_questionnaire_step(project, conn, questionnaire, questionnaire_name, step_id, step_title, step_type) do
    create("create_step", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, step_id: step_id, step_title: step_title, step_type: step_type})
  end

  def delete_questionnaire_step(project, conn, questionnaire, questionnaire_name, step_id, step_title, step_type) do
    create("delete_step", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, step_id: step_id, step_title: step_title, step_type: step_type})
  end

  def rename_questionnaire_step(project, conn, questionnaire, questionnaire_name, step_id, old_step_title, new_step_title) do
    create("rename_step", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, step_id: step_id, old_step_title: old_step_title, new_step_title: new_step_title})
  end

  def edit_settings(project, conn, questionnaire) do
    create("edit_settings", project, conn, questionnaire, %{questionnaire_name: questionnaire.name})
  end

  def edit_questionnaire_step(project, conn, questionnaire, questionnaire_name, step_id, step_title) do
    create("edit_step", project, conn, questionnaire, %{questionnaire_name: questionnaire_name, step_id: step_id, step_title: step_title})
  end

  def rename_questionnaire(project, conn, questionnaire, old_questionnaire_name, new_questionnaire_name) do
    create("rename", project, conn, questionnaire, %{
      old_questionnaire_name: old_questionnaire_name,
      new_questionnaire_name: new_questionnaire_name
    })
  end

  def delete_questionnaire(project, conn, questionnaire) do
    create("delete", project, conn, questionnaire, %{questionnaire_name: questionnaire.name})
  end
end
