defmodule SoundForge.Workflow.Orchestrator do
  @moduledoc """
  Composable staged pipeline runner.

  Ported from vyynl-sales-web `lib/mockup-pipeline/pipeline.ts`
  (`generateMockup`): the orchestration shape is
  idempotency check -> guard (cost-cap analog: quota / disk-space) ->
  work with retry backoff `[500, 2000, 5000]` ms -> validate -> persist,
  generalized into a keyword-configured `run/2`.

      Orchestrator.run(input,
        idempotency: fn input -> :miss | {:hit, result} end,           # optional
        guard: fn input -> :ok | {:error, reason} end,                 # optional
        work: fn input -> {:ok, result} | {:error, reason} end,        # required
        validate: fn result -> :ok | {:error, reason} end,             # optional
        persist: fn result -> {:ok, final} | {:error, reason} end,     # optional
        retry_backoff: [500, 2000, 5000],                              # default
        retryable?: fn reason -> boolean end,                          # default: always
        telemetry_metadata: %{}                                        # merged into events
      )

  Returns `{:ok, result}` or `{:error, stage, reason}` where stage is one of
  `:guard | :work | :validate | :persist`.

  Telemetry: emits `[:sound_forge, :workflow, stage]` for each executed stage
  (`stage` in `:idempotency | :guard | :work | :validate | :persist`) with
  measurements `%{duration: native_time}` (plus `%{attempt: n}` for `:work`)
  and metadata `%{outcome: :ok | :hit | :miss | :error | :blocked, reason: term | nil}`
  merged with `:telemetry_metadata`.
  """

  @default_backoff [500, 2000, 5000]

  @type stage :: :guard | :work | :validate | :persist
  @type result :: {:ok, term()} | {:error, stage(), term()}

  @spec run(term(), keyword()) :: result()
  def run(input, opts) when is_list(opts) do
    work = Keyword.fetch!(opts, :work)
    meta = Keyword.get(opts, :telemetry_metadata, %{})

    with :miss <- check_idempotency(input, Keyword.get(opts, :idempotency), meta),
         :ok <- check_guard(input, Keyword.get(opts, :guard), meta),
         {:ok, work_result} <- run_work(input, work, opts, meta),
         :ok <- run_validate(work_result, Keyword.get(opts, :validate), meta),
         {:ok, final} <- run_persist(work_result, Keyword.get(opts, :persist), meta) do
      {:ok, final}
    else
      {:hit, cached} -> {:ok, cached}
      {:error, _stage, _reason} = error -> error
    end
  end

  # -- stages -----------------------------------------------------------------

  defp check_idempotency(_input, nil, _meta), do: :miss

  defp check_idempotency(input, fun, meta) do
    {duration, outcome} = timed(fn -> fun.(input) end)

    case outcome do
      {:hit, cached} ->
        emit(:idempotency, %{duration: duration}, meta, :hit)
        {:hit, cached}

      :miss ->
        emit(:idempotency, %{duration: duration}, meta, :miss)
        :miss
    end
  end

  defp check_guard(_input, nil, _meta), do: :ok

  defp check_guard(input, fun, meta) do
    {duration, outcome} = timed(fn -> fun.(input) end)

    case outcome do
      :ok ->
        emit(:guard, %{duration: duration}, meta, :ok)
        :ok

      {:error, reason} ->
        emit(:guard, %{duration: duration}, meta, :blocked, reason)
        {:error, :guard, reason}
    end
  end

  defp run_work(input, fun, opts, meta) do
    backoff = Keyword.get(opts, :retry_backoff, @default_backoff)
    retryable? = Keyword.get(opts, :retryable?, fn _reason -> true end)
    sleep = Keyword.get(opts, :sleep, &Process.sleep/1)
    attempt_work(input, fun, backoff, retryable?, sleep, meta, 1)
  end

  defp attempt_work(input, fun, backoff, retryable?, sleep, meta, attempt) do
    {duration, outcome} = timed(fn -> fun.(input) end)

    case outcome do
      {:ok, result} ->
        emit(:work, %{duration: duration, attempt: attempt}, meta, :ok)
        {:ok, result}

      {:error, reason} ->
        emit(:work, %{duration: duration, attempt: attempt}, meta, :error, reason)

        case backoff do
          [delay | rest] ->
            if retryable?.(reason) do
              sleep.(delay)
              attempt_work(input, fun, rest, retryable?, sleep, meta, attempt + 1)
            else
              {:error, :work, reason}
            end

          [] ->
            {:error, :work, reason}
        end
    end
  end

  defp run_validate(_result, nil, _meta), do: :ok

  defp run_validate(result, fun, meta) do
    {duration, outcome} = timed(fn -> fun.(result) end)

    case outcome do
      :ok ->
        emit(:validate, %{duration: duration}, meta, :ok)
        :ok

      {:error, reason} ->
        emit(:validate, %{duration: duration}, meta, :error, reason)
        {:error, :validate, reason}
    end
  end

  defp run_persist(result, nil, _meta), do: {:ok, result}

  defp run_persist(result, fun, meta) do
    {duration, outcome} = timed(fn -> fun.(result) end)

    case outcome do
      {:ok, final} ->
        emit(:persist, %{duration: duration}, meta, :ok)
        {:ok, final}

      {:error, reason} ->
        emit(:persist, %{duration: duration}, meta, :error, reason)
        {:error, :persist, reason}
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp timed(fun) do
    start = System.monotonic_time()
    outcome = fun.()
    {System.monotonic_time() - start, outcome}
  end

  defp emit(stage, measurements, meta, outcome, reason \\ nil) do
    :telemetry.execute(
      [:sound_forge, :workflow, stage],
      measurements,
      Map.merge(meta, %{outcome: outcome, reason: reason})
    )
  end
end
