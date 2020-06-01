defmodule Ask.RespondentsFilter do
  defstruct [:disposition, :since]

  def parse(q) do
    %__MODULE__{}
    |> parse_diposition(q)
    |> parse_since(q)
  end

  defp parse_diposition(filter, q) do
    Map.put(filter, :disposition, extract(q, "disposition"))
  end

  defp parse_since(filter, q) do
    Map.put(filter, :since, extract(q, "since"))
  end

  defp extract(q, key) do
    {:ok, exp} = Regex.compile("(^|[ ])#{key}:(?<#{key}>[^ ]+)")
    capture = Regex.named_captures(exp, q)
    if capture, do: Map.get(capture, key), else: nil
  end
end
