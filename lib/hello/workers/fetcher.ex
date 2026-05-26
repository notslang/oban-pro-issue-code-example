defmodule Hello.Workers.Fetcher do
  use Oban.Pro.Worker,
    queue: :fetch,
    unique: [
      fields: [:args],
      keys: [:my_unique_arg]
    ]

  require Logger

  @impl true
  def process(%Oban.Job{args: %{"my_unique_arg" => unique, "another_arg" => another}}),
    do: Logger.info("running fetcher my_unique_arg=#{unique} another_arg=#{another}")
end
