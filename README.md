# Oban Pro Issue Reproduction

This repo reproduces an issue where the first job in a workflow is discarded via `unique`, but the second job gets inserted and stuck in the `suspended` state.

There are two workers:

- `Hello.Workers.Fetcher` - has `unique` set to throw away duplicates on the arg `my_unique_arg`
- `Hello.Workers.Processor` - no `unique` set. has a dependency on `Fetcher`.

These two workers are combined into a workflow and inserted by `Hello.insert_workflow`. The function `insert_workflows_with_duplicate` inserts this same workflow 3 times to cause duplicate `Fetcher` jobs to be dropped. The `Processor` jobs still get inserted.

On Oban Pro `v1.6.13` the `Processor` jobs get cancelled and eventually removed from the `oban_jobs` table.

On Oban Pro `v1.7.4` the `Processor` jobs get stuck in `suspended` and stay around. In a system with lots of these jobs, they eventually build up and hurt performance.

## How This Worked On Oban Pro `v1.6.13`

First I use these deps in `mix.exs`:

```
{:oban, "~> 2.20.3"},
{:oban_pro, "~> 1.6.13", repo: "oban"},
```

Next I start up the application with `iex -S mix` and run `Hello.insert_workflows_with_duplicate()`:

```
iex(1)> Hello.insert_workflows_with_duplicate()
[debug] QUERY OK source="oban_jobs" db=0.8ms queue=1.4ms idle=1403.9ms
DELETE FROM "oban_jobs" AS o0 []
↳ Hello.insert_workflows_with_duplicate/0, at: lib/hello.ex:20
[debug] inserted worker=Hello.Workers.Fetcher args=%{another_arg: "one", my_unique_arg: 123}
[debug] inserted worker=Hello.Workers.Processor args=%{another_arg: "one", my_unique_arg: 123}
[info] running fetcher my_unique_arg=123 another_arg=one
[debug] dropped duplicate worker=Hello.Workers.Fetcher args=%{another_arg: "two", my_unique_arg: 123}
[debug] inserted worker=Hello.Workers.Processor args=%{another_arg: "two", my_unique_arg: 123}
[debug] dropped duplicate worker=Hello.Workers.Fetcher args=%{another_arg: "three", my_unique_arg: 123}
[debug] inserted worker=Hello.Workers.Processor args=%{another_arg: "three", my_unique_arg: 123}
[info] running processor my_unique_arg=123 another_arg=one
```

Only the first `Fetcher` gets inserted while the others get dropped. All the `Processor` jobs get inserted. The first `Fetcher` runs, then the first `Processor` runs.

The remaining two `Processor` jobs are marked as `scheduled`:

```
postgres@localhost:hello_dev> select * from oban_jobs
+----+-----------+---------+-------------------------+------------------------------------------------+--------+--------->
| id | state     | queue   | worker                  | args                                           | errors | attempt >
|----+-----------+---------+-------------------------+------------------------------------------------+--------+--------->
| 22 | scheduled | process | Hello.Workers.Processor | {"another_arg": "two", "my_unique_arg": 123}   | []     | 0       >
| 24 | scheduled | process | Hello.Workers.Processor | {"another_arg": "three", "my_unique_arg": 123} | []     | 0       >
| 19 | completed | fetch   | Hello.Workers.Fetcher   | {"another_arg": "one", "my_unique_arg": 123}   | []     | 1       >
| 20 | completed | process | Hello.Workers.Processor | {"another_arg": "one", "my_unique_arg": 123}   | []     | 1       >
+----+-----------+---------+-------------------------+------------------------------------------------+--------+--------->
```

After about a minute they get transitioned to `cancelled` with the error `(Oban.Pro.WorkflowError) upstream job was deleted, workflow can't complete"`:

```
postgres@localhost:hello_dev> select * from oban_jobs
+----+-----------+---------+-------------------------+------------------------------------------------+------------------>
| id | state     | queue   | worker                  | args                                           | errors           >
|----+-----------+---------+-------------------------+------------------------------------------------+------------------>
| 19 | completed | fetch   | Hello.Workers.Fetcher   | {"another_arg": "one", "my_unique_arg": 123}   | []               >
| 20 | completed | process | Hello.Workers.Processor | {"another_arg": "one", "my_unique_arg": 123}   | []               >
| 22 | cancelled | process | Hello.Workers.Processor | {"another_arg": "two", "my_unique_arg": 123}   | ['{"at": "2026-05>
| 24 | cancelled | process | Hello.Workers.Processor | {"another_arg": "three", "my_unique_arg": 123} | ['{"at": "2026-05>
+----+-----------+---------+-------------------------+------------------------------------------------+------------------>
```

They remain in `cancelled` after the `completed` jobs get pruned by `DynamicPruner`:

```
postgres@localhost:hello_dev> select * from oban_jobs
+----+-----------+---------+-------------------------+------------------------------------------------+------------------>
| id | state     | queue   | worker                  | args                                           | errors           >
|----+-----------+---------+-------------------------+------------------------------------------------+------------------>
| 22 | cancelled | process | Hello.Workers.Processor | {"another_arg": "two", "my_unique_arg": 123}   | ['{"at": "2026-05>
| 24 | cancelled | process | Hello.Workers.Processor | {"another_arg": "three", "my_unique_arg": 123} | ['{"at": "2026-05>
+----+-----------+---------+-------------------------+------------------------------------------------+------------------>
```

Then finally the `cancelled` jobs get pruned by `DynamicPruner` and we're left with an empty table a few minutes later:

```
postgres@localhost:hello_dev> select * from oban_jobs
+----+-------+-------+--------+------+--------+---------+--------------+-------------+--------------+--------------+----->
| id | state | queue | worker | args | errors | attempt | max_attempts | inserted_at | scheduled_at | attempted_at | comp>
|----+-------+-------+--------+------+--------+---------+--------------+-------------+--------------+--------------+----->
+----+-------+-------+--------+------+--------+---------+--------------+-------------+--------------+--------------+----->
```

I have no idea if this behavior was intentional, but it did clear out the processing jobs that would never run.

It would be even better if we could prevent those processing jobs from being inserted in the first place when their dependency gets dropped as a duplicate.

## How This Works On Oban Pro `v1.7.4`

I start up the application with `iex -S mix` and run `Hello.insert_workflows_with_duplicate()`:

```
iex(1)> Hello.insert_workflows_with_duplicate()
[debug] QUERY OK source="oban_jobs" db=2.5ms queue=5.0ms idle=1414.8ms
DELETE FROM "oban_jobs" AS o0 []
↳ Hello.insert_workflows_with_duplicate/0, at: lib/hello.ex:20
[debug] inserted worker=Hello.Workers.Fetcher args=%{another_arg: "one", my_unique_arg: 123}
[debug] inserted worker=Hello.Workers.Processor args=%{another_arg: "one", my_unique_arg: 123}
[debug] dropped duplicate worker=Hello.Workers.Fetcher args=%{another_arg: "two", my_unique_arg: 123}
[debug] inserted worker=Hello.Workers.Processor args=%{another_arg: "two", my_unique_arg: 123}
[info] running fetcher my_unique_arg=123 another_arg=one
[debug] dropped duplicate worker=Hello.Workers.Fetcher args=%{another_arg: "three", my_unique_arg: 123}
[debug] inserted worker=Hello.Workers.Processor args=%{another_arg: "three", my_unique_arg: 123}
[info] running processor my_unique_arg=123 another_arg=one
```

Only the first `Fetcher` gets inserted while the others get dropped. All the `Processor` jobs get inserted. The first `Fetcher` runs, then the first `Processor` runs. The `Processor` jobs that didn't run are marked as `suspended`:

```
postgres@localhost:hello_dev> select * from oban_jobs
+----+-----------+---------+-------------------------+------------------------------------------------+>
| id | state     | queue   | worker                  | args                                           |>
|----+-----------+---------+-------------------------+------------------------------------------------+>
| 4  | suspended | process | Hello.Workers.Processor | {"another_arg": "two", "my_unique_arg": 123}   |>
| 6  | suspended | process | Hello.Workers.Processor | {"another_arg": "three", "my_unique_arg": 123} |>
| 1  | completed | fetch   | Hello.Workers.Fetcher   | {"another_arg": "one", "my_unique_arg": 123}   |>
| 2  | completed | process | Hello.Workers.Processor | {"another_arg": "one", "my_unique_arg": 123}   |>
+----+-----------+---------+-------------------------+------------------------------------------------+>
```

Eventually the `completed` jobs get pruned, but the `suspended` jobs are left:

```
postgres@localhost:hello_dev> select * from oban_jobs
+----+-----------+---------+-------------------------+------------------------------------------------+>
| id | state     | queue   | worker                  | args                                           |>
|----+-----------+---------+-------------------------+------------------------------------------------+>
| 4  | suspended | process | Hello.Workers.Processor | {"another_arg": "two", "my_unique_arg": 123}   |>
| 6  | suspended | process | Hello.Workers.Processor | {"another_arg": "three", "my_unique_arg": 123} |>
+----+-----------+---------+-------------------------+------------------------------------------------+>
```

It doesn't seem like those `suspended` jobs ever get cleaned up.
