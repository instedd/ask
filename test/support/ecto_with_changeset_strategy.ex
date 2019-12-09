defmodule ExMachina.EctoWithChangesetStrategy do
  use ExMachina.Strategy, function_name: :insert

  def handle_insert(record, %{repo: repo} = params) do
    strict = Map.get(params, :strict, false)
    inserted = record |> repo.insert!
    changeset = apply(inserted.__struct__, :changeset, [inserted])
    if not changeset.valid?, do: raise "Invalid changeset: #{changeset.errors |> inspect}"
    case strict do
      true ->
        if not (changeset.changes == %{}), do: raise "Missing changes: #{changeset.changes |> inspect}"
        inserted
      _ ->
        repo.update!(changeset)
    end
  end
end
