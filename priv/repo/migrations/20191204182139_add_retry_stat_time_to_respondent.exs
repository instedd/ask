defmodule Ask.Repo.Migrations.AddRetryStatTimeToRespondent do
  use Ecto.Migration

  def change do
    alter table(:respondents) do
      add :retry_stat_time, :string
    end
  end
end
