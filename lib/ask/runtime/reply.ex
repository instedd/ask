defmodule Ask.Runtime.Reply do
  defstruct stores: [], steps: [], disposition: nil

  def prompts(%{steps: steps}) do
    Enum.flat_map(steps, fn(step) -> step.prompts end)
  end

  def disposition(%{disposition: disposition}) do
    disposition
  end

  def steps(%{steps: steps}) do
    steps
  end

  def stores(%{stores: stores}) do
    stores
  end

  def stores(_) do
    []
  end
end

defmodule Ask.Runtime.ReplyStep do
  defstruct prompts: [], id: nil, title: nil, type: nil, choices: [], min: nil, max: nil
  alias __MODULE__

  def new(prompts, title, type \\ "explanation", id \\ nil, choices \\ [], min \\ nil, max \\ nil)

  def new([nil], _, _, _, _, _, _) do
    nil
  end

  def new(prompts, title, type, id, choices, min, max) do
    %ReplyStep{prompts: prompts, id: id, title: title, type: type, choices: choices, min: min, max: max}
  end

  def title_with_index(step, index) do
    case length(step.prompts) do
      1 -> step.title
      _ -> case step.title do
             nil -> ""
             "" -> ""
             _ -> "#{step.title} #{index}"
           end
    end
  end
end
