defmodule Common.ExponentialBackoff.CoordinatorSupervisor do
  @moduledoc """
  ExponentialBackoff Coordinator
  """

  use GenServer

  require Logger

  alias Common.ExponentialBackoff
  alias Common.ExponentialBackoff.BoundInterval

  # milliseconds
  @block_interval 5_000

  defmodule State do
    defstruct ~w(task bound_interval)a
  end

  def child_spec([named_arguments]) when is_map(named_arguments),
    do: child_spec([named_arguments, []])

  def child_spec([_named_arguments, gen_server_options] = start_link_arguments)
      when is_list(gen_server_options) do
    Supervisor.child_spec(
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, start_link_arguments},
        type: :supervisor
      },
      []
    )
  end

  def start_link(_opts, _gen_server_options \\ []) do
    block_interval = @block_interval
    minimum_interval = div(block_interval, 2)
    bound_interval = BoundInterval.within(minimum_interval..(minimum_interval * 10))

    state = %State{task: nil, bound_interval: bound_interval}

    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    %{bound_interval: bound_interval} = state

    Process.send_after(self(), :task_index, bound_interval.current)

    {:ok, state}
  end

  @impl true
  def handle_info(:task_index, state) do
    {:noreply,
     %State{
       state
       | task:
           Task.Supervisor.async_nolink(ExponentialBackoff.TaskSupervisor, __MODULE__, :task, [])
     }}
  end

  @impl true
  def handle_info(
        {ref, return_task},
        %State{bound_interval: bound_interval, task: %Task{ref: ref}} = state
      ) do
    Process.demonitor(ref, [:flush])

    new_bound_interval =
      case return_task do
        :increase ->
          BoundInterval.increase(bound_interval)

        _ ->
          BoundInterval.decrease(bound_interval)
      end

    interval = new_bound_interval.current

    Logger.info(fn ->
      [
        "Task Return is #{return_task}. Checking if index needs to task in ",
        to_string(interval),
        "ms."
      ]
    end)

    Process.send_after(self(), :task_index, interval)

    {:noreply, %State{state | bound_interval: new_bound_interval, task: nil}}
  end

  @impl true
  def handle_info({ref, {:error, :etimedout}}, %State{task: %Task{ref: ref}} = state) do
    send(self(), :task_index)

    {:noreply, %State{state | task: nil}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %State{task: %Task{pid: pid, ref: ref}} = state
      ) do
    send(self(), :task_index)

    {:noreply, %State{state | task: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %State{task: nil} = state) do
    send(self(), :task_index)

    {:noreply, %State{state | task: nil}}
  end

  def task(), do: Enum.random(~w(increase decrease)a)
end
