defmodule Pooly.PoolServer do
  use GenServer
  import Supervisor.Spec

  # Define Struct to maintain the state of the server
  defmodule State do
    defstruct pool_sup: nil, worker_sup: nil, monitors: nil, size: nil, workers: nil, name: nil, mfa: nil, max_overflow: nil, overflow: nil, waiting: nil
  end

  #######
  # API #
  #######

  # start_link takes pool_sup as well as pool_config. Creates a named process.
  def start_link(pool_sup, pool_config) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_config], name: name(pool_config[:name]))
  end

  def checkout(pool_name, block, timeout) do
    GenServer.call(name(pool_name), {:checkout, block}, timeout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

   def terminate(_reason, _state) do
     :ok
   end

  #############
  # Callbacks #
  #############

  # This callback is always called by GenServer.start_link/3. Assigns the
  # supervisor pid to the State structure, and calls init/2. init/2 is a series
  # of functions that pattern match on potential pool_config options.
  def init([pool_sup, pool_config]) when is_pid(pool_sup) do

    # Since we DO want the worker processes to crash if the server crashes, but
    # DON'T want the server to crash a worker process crashes, we trap exit
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    waiting = :queue.new
    init(pool_config, %State{pool_sup: pool_sup, monitors: monitors, waiting: waiting, overflow: 0})
  end

  # These next four functions will pattern match on pool_config, attempt to
  # find specific objects, and add them to the state.

  def init([{:name, name}|rest], state) do
    init(rest, %{state | name: name})
  end

  def init([{:mfa, mfa}|rest], state) do
    init(rest, %{state | mfa: mfa})
  end

  def init([{:size, size}|rest], state) do
    init(rest, %{state | size: size})
  end

  def init([{:max_overflow, max_overflow}|rest], state) do
    init(rest, %{state | max_overflow: max_overflow})
  end

  # Base case. Once the options list has been evaluated. Sends a message to
  # start the worker supervisor
  def init([], state) do
    send(self, :start_worker_supervisor)
    {:ok, state}
  end

  # Ignores any other option not provided, continues to iterate
  def init([_|rest], state) do
    init(rest, state)
  end

  def handle_call({:checkout, block}, {from_pid, _ref} = from, state) do
    %{workers: workers,
      monitors: monitors,
      worker_sup: worker_sup,
      overflow: overflow,
      waiting: waiting,
      max_overflow: max_overflow} = state

    # If workers is empty, then no workers can be assigned. Otherwise, this will
    # assign the worker to the calling process.
    case workers do
      [worker|rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] when max_overflow > 0 and overflow < max_overflow ->
        {worker, ref} = new_worker(worker_sup, from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | overflow: overflow + 1}}

      # If nothing available and user wants to block (aka wait), this places the
      # user in the queue.
      [] when block == true ->
        ref = Process.monitor(from_pid)
        waiting = :queue.in({from, ref}, waiting)
        {:noreply, %{state | waiting: waiting}, :infinity}

      # Replies with a status of ":full" if the user doesn't want to wait and no
      # available workers or overflow.
      [] ->
        {:reply, :full, state}
    end
  end

  # Replies with number of available workers and number of checked out workers.
  # Also retunrs the "state" (poor name) of the overflow status, as either
  # :overflow, :full or :ready. Private function state_name returns status.
  def handle_call(:status, _from, %{workers: workers, monitors: monitors} = state) do
    {:reply, {state_name(state), length(workers), :ets.info(monitors, :size)}, state}
  end

  def handle_cast({:checkin, worker}, %{monitors: monitors} = state) do

    # If the return is a pid and ref, then we demonitor the consumer process and
    # remove the entry from the ETS. If entry not found, then nothing is done.
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_checkin(pid, state)
        {:noreply, new_state}
      [] ->
        {:noreply, state}
    end
  end

  def handle_info(:start_worker_supervisor, state = %{pool_sup: pool_sup, name: name, mfa: mfa, size: size}) do

    # Starts a worker supervisor as a child process. Uses a private function,
    # supervisor_spec to start the child supervisor.
    {:ok, worker_sup} = Supervisor.start_child(pool_sup, supervisor_spec(name, mfa))

    # Private function that creates a specified number of workers (size) within
    # the newly created supervisor and returns their pids as a list.
    workers = prepopulate(size, worker_sup)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  # When a monitored process goes down, this will remove it from the ETS table
  # of monitored processes and adds the worker back to the into the state so it.
  # can be used again
  def handle_info({:DOWN, ref, _, _, _}, state = %{monitors: monitors, workers: workers}) do
      case :ets.match(monitors, {:"$1", ref}) do

      # $1 will return the first element of the tuple from the match were ref
      # is the second element. In this case, it's the pid in the ETS table.
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid|workers]}
        {:noreply, new_state}
      [[]] ->
        {:noreply, state}
    end
  end

  # This will pattern match when the worker supervisor exits. This lets us know
  # why it crashed and will stop the pool_server as well.
  def handle_info({:EXIT, worker_sup, reason}, state = %{worker_sup: worker_sup}) do
    {:stop, reason, state}
  end

  # Since we are trapping exits in the event that a worker process goes down, we
  # can handle that separately here. Demonitors, removes entry from ETS table,
  # and a new workers is created and inserted into the workers field.
  def handle_info({:EXIT, pid, _reason}, state = %{monitors: monitors, workers: workers, pool_sup: pool_sup}) do
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)

        # Creates a replacement worker using the private function new_worker and
        # combines it with the existing workers list from the current state.
        new_state = handle_worker_exit(pid, state)
        {:noreply, new_state}
      _ ->
        {:noreply, state}
    end
  end

  def terminate(_reason, _state) do
    :ok
  end

  #####################
  # Private Functions #
  #####################

  # Returns the name of the pool server as an atom
  defp name(pool_name) do
    :"#{pool_name}Server"
  end

  # Default prepoulate starting point. Initializes worker collector list.
  defp prepopulate(size, sup) do
    prepopulate(size, sup, [])
  end

  # When size counter drops below 1, returns the list of workers
  defp prepopulate(size, _sup, workers) when size < 1 do
    workers
  end

  # Decreases the size, adds a new worker to the workers list via the private
  # function new_worker.
  defp prepopulate(size, sup, workers) do
    prepopulate(size - 1, sup, [new_worker(sup) | workers])
  end

  # Spawns a new worker process and returns the pid. Empty arguments array is
  # passed to start_child/2. Since Pooly.WorkerSupervisor has set a restart
  # strategy (:simple_one_for_one), the child specification has already been
  # defined.
  defp new_worker(sup) do
    {:ok, worker} = Supervisor.start_child(sup, [[]])
    Process.link(worker)
    worker
  end

  # Used for overflow workers. Needs the from_pid to setup monitor.
  defp new_worker(sup, from_pid) do
    pid = new_worker(sup)
    ref = Process.monitor(from_pid)
    {pid, ref}
  end

  # Helper function to return a unique child specification, of a supervisor
  # variety, with the id option set to the name from pool_config and
  # "WorkerSupervisor". Those id options have to be unique. If it's not, you'll
  # get an :already_started error.
  defp supervisor_spec(name, mfa) do
    opts = [id: name <> "WorkerSupervisor", shutdown: 10000, restart: :temporary]

    # This is the child specification. Both mfa and the pid of this server are
    # included
    supervisor(Pooly.WorkerSupervisor, [self, mfa], opts)
  end

  def handle_checkin(pid, state) do
    %{worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      overflow: overflow} = state

    # Checks the pool to see if any overflow. If so, terminates process via
    # private function dismiss_worker, reduces overflow count by one. If no
    # overflow, simply adds the pid back to the workers pool.
    # TODO add "monitor: empty" to state here once implemented.
    if overflow > 0 do
      :ok = dismiss_worker(worker_sup, pid)
      %{state | waiting: :empty, overflow: overflow - 1}
    else
      %{state | waiting: :empty, workers: [pid | workers], overflow: 0}
    end
  end

  # This simply checks to see if the pool is overflowed. If it is, we just
  # decrement the counter. No need to add the worker back to the pool if it is
  # overflowed. Not sure why we pull monitors from state here...it's unused.
  def handle_worker_exit(pid, state) do
    %{worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      overflow: overlfow} = state

    if overlfow > 0 do
      %{state | overlfow: overlfow - 1}
    else
      %{state | workers: [new_worker(worker_sup) | workers]}
    end
  end

  # Unlinks the woker and terminates the child.
  defp dismiss_worker(sup, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(sup, pid)
  end

  # Pattern mathes only when overflow is less than 1. The next function matches
  # if max_overflow reached. The third, anything else.
  defp state_name(%State{overflow: overflow, max_overflow: max_overflow, workers: workers}) when overflow < 1 do
    case length(workers) == 0 do
      true ->
        if max_overflow < 1 do
          :full
        else
          :overflow
        end
      false ->
        :ready
    end
  end

  # Pattern matches when overflow equals max_overflow. max_overflow is pulled
  # then matched in the same sentence. Really like this.
  # TODO test without the "State" struct. Should be able to just use a map
  defp state_name(%State{overflow: max_overflow, max_overflow: max_overflow}) do
    :full
  end

  # Anything else is just an :overflow status
  defp state_name(_state), do: :overflow
end
