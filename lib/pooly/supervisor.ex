defmodule Pooly.Supervisor do
  use Supervisor

  #######
  # API #
  #######

  def start_link(pool_config) do
    Supervisor.start_link(__MODULE__, pool_config)
  end

  #############
  # Callbacks #
  #############

  def init(pool_config) do

    # Pooly.Server.start_link/2 takes two arguments: pid of the top-level
    # supervisor and the pool configuration.
    children = [
      worker(Pooly.Server, [self, pool_config])
    ]

    # Uses :one_for_all, which ensures that if either Supervisor or
    # WorkerSupervisor goes down, everything goes down.
    opts = [strategy: :one_for_all]

    supervise(children, opts)
  end
end
