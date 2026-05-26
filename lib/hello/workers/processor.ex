defmodule Hello.Workers.Processor do
  use Oban.Pro.Worker, queue: :process

  require Logger

  @impl true
  def process(%Oban.Job{args: %{"my_unique_arg" => unique, "another_arg" => another}}),
    do: Logger.info("running processor my_unique_arg=#{unique} another_arg=#{another}")
end
