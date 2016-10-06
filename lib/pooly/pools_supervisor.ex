defmodule Pooly.PoolsSupervisor do
  use Supervisor

  #######
  # API #
  #######

  # Starts the PoolsSupervisor and makes it a self-named process
  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  #############
  # Callbacks #
  #############

  # Supervisor is intially started with no pools attached. We will instead
  # validate the pool configuration before creating any pools. As a result, we
  # only supply the restart strategy.
  def init(_) do

    # Ensure that a crash in one pool doesn't affect any other pool.
    opts = [strategy: :one_for_one]

    supervise([], opts)
  end
end
