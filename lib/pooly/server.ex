defmodule Pooly.Server do
  use GenServer
  import Supervisor.Spec

  # Define Struct to maintain the state of the server
  defmodule State do
    defstruct sup: nil, size: nil, mfa: nil, monitors: nil, worker_sup: nil, workers: nil
  end

  #######
  # API #
  #######

  # sup is the top level supervisor. pool_config is the pool configuration
  def start_link(sup, pool_config) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: __MODULE__)
  end

  def checkout do
    GenServer.call(__MODULE__, :checkout)
  end

  def checkin(worker_pid) do
    GenServer.cast(__MODULE__, {:checkin, worker_pid})
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  #############
  # Callbacks #
  #############

  # This callback is always called by GenServer.start_link/3. Assigns the
  # supervisor pid to the State structure, and calls init/2. init/2 is a series
  # of functions that pattern match on potential pool_config options.
  def init([sup, pool_config]) when is_pid(sup) do
    monitors = :ets.new(:monitors, [:private])
    init(pool_config, %State{sup: sup, monitors: monitors})
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

  def handle_call(:checkout, {from_pid, _ref}, %{workers: workers, monitors: monitors} = state) do

    # If workers is empty, then no workers can be assigned. Otherwise, this will
    # assign the worker to the calling process.
    case workers do
      [worker|rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}
      [] ->
        {:reply, :noproc, state}
    end
  end

  def handle_cast({:checkin, worker}, %{workers: workers, monitors: monitors} = state) do

    # If the return is a pid and ref, then we demonitor the consumer process and
    # remove the entry from the ETS. If entry not found, then nothing is done.
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        {:noreply, %{state | workers: [pid|workers]}}
      [] ->
        {:noreply, state}
    end
  end

  def handle_call(:status, _from, %{workers: workers, monitors: monitors} = state) do
    {:reply, {length(workers), :ets.info(monitors, :size)}, state}
  end

  # When a monitored process goes down, this will remove it from the ETS table
  # of monitored processes and adds the worker back to the into the state.
  def handle_info({:DOWN, ref, _, _, _}, state = %{monitors: monitors, workers: workers}) do
    case :ets.match(monitors, {:"$1", ref}) do
      # $1 will return the first element of the tuple from the match were ref
      # is the second element. In this case, it's the pid in the ETS table.
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid|workers]}
        {:noreply, state}
      [[]] ->
        {:noreply, state}
    end
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
