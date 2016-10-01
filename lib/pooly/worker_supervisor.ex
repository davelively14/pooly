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
    # Specifies that the worker is always to be restarted (:permanent) and
    # passes the function, f, that starts the worker.
    worker_opts = [restart: :permanent, function: f]

    # Creates a list of the child processes. The worker function creates a child
    # specification.
    children = [worker(m, a, worker_opts)]

    # The simple_one_for_one strategy allows for dynamic building of children
    # based on a single specification. The max_restarts indicates the maximum
    # number of restarts in max_seconds amount of time before termination. By
    # default, this is set to max_restarts: 3, max_seconds: 5
    opts = [strategy: :simple_one_for_one, max_restarts: 5, max_seconds: 5]

    # The return value must be a supervisor specification
    supervise(children, opts)
  end
end
