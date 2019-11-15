defmodule Ask.FunctionalCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case
      alias Ask.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ask.ModelCase
      import Ask.Factory

      def setup_survey(opts \\ %{}) do
        survey = insert(:survey)
        %{survey: survey, respondent: :ok}
      end

      def start_survey() do
        :ok
      end

      def assert_message_received(respondent, message) do
        assert true
      end
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Ask.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Ask.Repo, {:shared, self()})
    end

    :ok
  end

end
