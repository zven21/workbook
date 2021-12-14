defmodule Common.ExponentialBackoff.Supervisor do
  @moduledoc """
  Supervises `ExponentialBackoff.TaskSupervisor` and `ExponentialBackoff.CoordinatorSupervisor`
  """

  use Supervisor

  require Logger

  alias Common.ExponentialBackoff

  def child_spec([]) do
    child_spec([nil, []])
  end

  def child_spec([init_arguments]) do
    child_spec([init_arguments, []])
  end

  def child_spec([_init_arguments, _gen_server_options] = start_link_arguments) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, start_link_arguments},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  def start_link(arguments, gen_server_options \\ []) do
    Supervisor.start_link(__MODULE__, arguments, gen_server_options)
  end

  @impl Supervisor
  def init(_opts) do
    Logger.info("ExponentialBackoff Supervisor Stared")

    Supervisor.init(
      [
        {Task.Supervisor, name: ExponentialBackoff.TaskSupervisor},
        {ExponentialBackoff.CoordinatorSupervisor,
         ["initial", [name: ExponentialBackoff.CoordinatorSupervisor]]}
      ],
      strategy: :one_for_one
    )
  end
end
