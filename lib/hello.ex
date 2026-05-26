defmodule Hello do
  @moduledoc """
  Hello keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias Hello.Workers.Fetcher
  alias Hello.Workers.Processor
  alias Oban.Pro.Workflow

  import Ecto.Query

  require Logger

  def insert_workflows_with_duplicate do
    # clear out all jobs
    from(Oban.Job) |> Hello.Repo.delete_all()

    # insert jobs. all jobs are given the same `my_unique_arg` so uniqueness
    # controls cause duplicates to be dropped.
    insert_workflow(123, "one")
    insert_workflow(123, "two")
    insert_workflow(123, "three")
  end

  def insert_workflow(my_unique_arg, another_arg) do
    args = %{my_unique_arg: my_unique_arg, another_arg: another_arg}

    Workflow.new()
    |> Workflow.add(:fetcher, Fetcher.new(args))
    |> Workflow.add(:processor, Processor.new(args), deps: [:fetcher])
    |> Oban.insert_all()
    |> Enum.each(fn
      job = %{conflict?: true} ->
        Logger.debug("dropped duplicate worker=#{job.worker} args=#{inspect(args)}")

      job ->
        Logger.debug("inserted worker=#{job.worker} args=#{inspect(args)}")
    end)
  end
end
