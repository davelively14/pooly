defmodule Pooly.PoolSupervisor do
  use Supervisor

  #######
  # API #
  #######

  # Starts the Supervisor with a unique name. Not necessary, but helps to
  # pinpoint them in :observer
  def start_link(pool_config) do
    Supervisor.start_link(__MODULE__, pool_config, name: :"#{pool_config[:name]}Supervisor")
  end

  #############
  # Callbacks #
  #############

  def init(pool_config) do

    # If the PoolServer goes down, restarts everything
    opts = [ strategy: :one_for_all ]

    # Even though we named this server process, we are still passing in the pid
    # of this process in order to reuse much of the code implementation from
    # previous versions.
    children = [
      worker(Pooly.PoolServer, [self, pool_config])
    ]

    supervise(children, opts)
  end
end
