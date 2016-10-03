defmodule Pooly.Server do
  use GenServer
  import Supervisor.Spec

  # Define Struct to maintain the state of the server
  defmodule State do
    defstruct sup: nil, size: nil, mfa: nil
  end

  #######
  # API #
  #######

  # sup is the top level supervisor. pool_config is the pool configuration
  def start_link(sup, pool_config) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: __MODULE__)
  end

  #############
  # Callbacks #
  #############

  # This callback is always called by GenServer.start_link/3. Assigns the
  # supervisor pid to the State structure, and calls init/2. init/2 is a series
  # of functions that pattern match on potential pool_config options.
  def init([sup, pool_config]) when is_pid(sup) do
    init(pool_config, %State{sup: sup})
  end

  # Pattern match for the mfa option in pool_config and stores in state
  def init([{:mfa, mfa}|rest], state) do
    init(rest, %{state | mfa: mfa})
  end

  # Pattern match for the size option in pool_config and stores in state
  def init([{:size, size}|rest], state) do
    init(rest, %{state | size: size})
  end

  # Ignores any other option, continues to iterate over of the list
  def init([_|rest], state) do
    init(rest, state)
  end

  # Base case once the options list has been evaluated. Sends a message to start
  # the worker supervisor.
  def init([], state) do
    send(self, :start_worker_supervisor)
    {:ok, state}
  end

  def handle_info(:start_worker_supervisor, state = %{sup: sup, mfa: mfa, size: size}) do
    {:ok, worker_sup} = Supervisor.start_child(sup, supervisor_spec(mfa))

    # Private function that creates "size" number of workers with the newly
    # created supervisor.
    workers = prepopulate(size, worker_sup)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  #####################
  # Private Functions #
  #####################

  # Starts the process as a Supervisor instead of a standard worker. Supervisor
  # will not restart (:temporary) by default. We will use coustom recovery rules
  defp supervisor_spec(mfa) do
    opts = [restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [mfa], opts)
  end

  # Default preopulate starting point. Initializes worker result list to empty
  defp prepopulate(size, sup) do
    prepopulate(size, sup, [])
  end

  # When size counter drops below 1, returns workers list to top.
  defp prepopulate(size, _sup, workers) when size < 1 do
    workers
  end

  # Decreases size, adds new_worker to the list of workers.
  defp prepopulate(size, sup, workers) do
    prepopulate(size - 1, sup, [new_worker(sup) | workers])
  end

  # Spawns a new worker process and returns the pid. Empty arguments array is
  # passed to start_child/2. Since Pooly.WorkerSupervisor has set a restart
  # strategy (:simple_one_for_one), the child specification has already been
  # defined. 
  defp new_worker(sup) do
    {:ok, worker} = Supervisor.start_child(sup, [[]])
    worker
  end
end
