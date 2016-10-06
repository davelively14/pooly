defmodule Pooly.Supervisor do
  use Supervisor

  #######
  # API #
  #######

  # Pooly.Supervisor is now a named process, which allows other processes to
  # reference this by name, in this case the module (Pooly.Supervisor)
  def start_link(pools_config) do
    Supervisor.start_link(__MODULE__, pools_config, name: __MODULE__)
  end

  #############
  # Callbacks #
  #############

  def init(pools_config) do

    # Since Poly.Server is a named process, we no longer have to pass it to the
    # Pooly.Server worker
    children = [
      supervisor(Pooly.PoolsSupervisor, []),
      worker(Pooly.Server, [pools_config])
    ]

    # Uses :one_for_all, which ensures that if either Supervisor or
    # either child crashes, everything crashes.
    opts = [strategy: :one_for_all]

    supervise(children, opts)
  end
end
