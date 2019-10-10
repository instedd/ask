defmodule Ask.Stats do
  @behaviour Ecto.Type
  alias __MODULE__

  defstruct total_received_sms: 0,
            total_sent_sms: 0,
            total_call_time: nil,
            total_call_time_seconds: nil,
            attempts: nil,
            total_attempts: nil

  def type, do: :longtext

  def cast(%Stats{} = stats) do
    {:ok, stats}
  end

  def cast(%{
        total_received_sms: total_received_sms,
        total_sent_sms: total_sent_sms,
        total_call_time: total_call_time,
        total_call_time_seconds: total_call_time_seconds,
        attempts: attempts,
        total_attempts: total_attempts
      }) do
    {:ok,
     %Stats{
       total_received_sms: total_received_sms,
       total_sent_sms: total_sent_sms,
       total_call_time: total_call_time,
       total_call_time_seconds: total_call_time_seconds,
       attempts: attempts,
       total_attempts: total_attempts
      }}
  end

  def cast(%{} = map) do
    cast(%{
      total_received_sms: map["total_received_sms"],
      total_sent_sms: map["total_sent_sms"],
      total_call_time: map["total_call_time"],
      total_call_time_seconds: map["total_call_time_seconds"],
      attempts: map["attempts"],
      total_attempts: map["total_attempts"]
    })
  end

  def cast(nil), do: {:ok, %Stats{}}
  def cast(_), do: :error

  def load(string) when is_binary(string), do: cast(Poison.decode!(string))
  def load(_), do: :error

  def dump(%Stats{} = stats), do: Poison.encode(stats)
  def dump(_), do: :error

  def total_received_sms(%Stats{total_received_sms: count}), do: count

  def total_received_sms(%Stats{} = stats, count) do
    %{stats | total_received_sms: count}
  end

  def total_sent_sms(%Stats{total_sent_sms: count}), do: count

  def total_sent_sms(%Stats{} = stats, count) do
    %{stats | total_sent_sms: count}
  end

  def total_call_time(stats),
    do: "#{total_call_time_minutes(stats)}m #{total_call_time_minutes_rem(stats)}s"

  defp total_call_time_minutes(stats), do: (total_call_time_seconds(stats) / 60) |> Kernel.trunc()
  defp total_call_time_minutes_rem(stats), do: rem(total_call_time_seconds(stats), 60)

  def total_call_time_seconds(%Stats{total_call_time: nil, total_call_time_seconds: nil}), do: 0

  def total_call_time_seconds(%Stats{total_call_time: minutes, total_call_time_seconds: nil}),
    do: (minutes * 60) |> Kernel.trunc()

  def total_call_time_seconds(total_call_time_seconds: nil), do: 0

  def total_call_time_seconds(%Stats{total_call_time_seconds: seconds}) when seconds != nil,
    do: seconds

  def total_call_time_seconds(%Stats{} = stats, count),
    do: %{stats | total_call_time_seconds: count}

  def add_received_sms(%Stats{total_received_sms: total} = stats, count \\ 1),
    do: %{stats | total_received_sms: total + count}

  def add_sent_sms(%Stats{total_sent_sms: total} = stats, count \\ 1),
    do: %{stats | total_sent_sms: total + count}

  def attempts(%Stats{attempts: nil}, :sms), do: 0
  def attempts(%Stats{attempts: %{"sms" => total}}, :sms), do: total
  def attempts(%Stats{attempts: _}, :sms), do: 0

  def attempts(%Stats{attempts: nil}, :ivr), do: 0
  def attempts(%Stats{attempts: %{"ivr" => total}}, :ivr), do: total
  def attempts(%Stats{attempts: _}, :ivr), do: 0

  def attempts(%Stats{attempts: nil}, :mobileweb), do: 0
  def attempts(%Stats{attempts: %{"mobileweb" => total}}, :mobileweb), do: total
  def attempts(%Stats{attempts: _}, :mobileweb), do: 0

  def attempts(%Stats{total_attempts: nil}, :total), do: 0
  def attempts(%Stats{total_attempts: total}, :total), do: total
  def attempts(%Stats{}, :total), do: 0

  def add_attempt(%Stats{total_attempts: nil} = stats, mode) do
    stats = %{stats | total_attempts: 1}
    add_mode_attempt(stats, mode)
  end

  def add_attempt(%Stats{total_attempts: total} = stats, mode) do
    stats = %{stats | total_attempts: total + 1}
    add_mode_attempt(stats, mode)
  end

  def add_attempt(stats, mode) do
    stats = Map.put(stats, "total_attempts", 1)
    add_mode_attempt(stats, mode)
  end

  defp add_mode_attempt(%Stats{attempts: nil} = stats, mode), do:
    %{stats | attempts: %{ Atom.to_string(mode) => 1 }}

  defp add_mode_attempt(%Stats{attempts: %{ "sms" => total } = attempts } = stats, :sms), do:
    %{stats | attempts: %{attempts | "sms" => total + 1}}

  defp add_mode_attempt(%Stats{attempts: %{ "ivr" => total } = attempts } = stats, :ivr), do:
    %{stats | attempts: %{attempts | "ivr" => total + 1}}

  defp add_mode_attempt(%Stats{attempts: %{ "mobileweb" => total } = attempts } = stats, :mobileweb), do:
    %{stats | attempts: %{attempts | "mobileweb" => total + 1}}

  defp add_mode_attempt(%Stats{attempts: attempts} = stats, mode), do:
  %{stats | attempts: Map.put(attempts, Atom.to_string(mode), 1)}
end
