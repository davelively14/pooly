defmodule Pooly.WorkerSupervisor do
  use Supervisor

  #######
  # API #
  #######

  # Pattern match to ensure that the passed variable, mfa, is a 3 element tuple
  # The variable mfa stands for Module, Function, Argument.
  def start_link({_,_,} = mfa) do
    Supervisor.start_link(__MODULE__, mfa)
  end

  #############
  # Callbacks #
  #############

  def init({m,f,a}) do
    # Specifies that the worker is always to be restarted and passes the
    # function that starts the worker
    worker_opts = [restart: :permanent, function: f]

    # Creates a list of the child processes
    children = [worker(m, a, worker_opts)]

    opts = [strategy: :simple_one_for_one, max_restarts: 5, max_seconds: 5]

    supervise(children, opts)
  end
end
