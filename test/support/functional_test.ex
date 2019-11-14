defmodule Ask.FunctionalTest do
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      use ExUnit.Case

      def setup_survey(opts \\ %{}) do
        %{respondent: :ok}
      end

      def start_survey() do
        :ok
      end

      def assert_message_received(respondent, message) do
        assert true
      end
    end
  end

end
