defmodule Ask.TestHelpers do
  defmacro __using__(_) do
    quote do
      def create_project_for_user(user, options \\ []) do
        level = options[:level] || "owner"
        archived = options[:archived] || false
        project = insert(:project, archived: archived)
        insert(:project_membership, user: user, project: project, level: level)
        project
      end
    end
  end
end
