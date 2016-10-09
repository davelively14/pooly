defmodule SampleWorker do
  use GenServer

  #######
  # API #
  #######

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  # Tells process to stay alive for a designated amount of time
  def work_for(pid, duration) do
    GenServer.cast(pid, {:work_for, duration})
  end

  #############
  # Callbacks #
  #############

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  # Sleeps for a designated amount of time, then terminates normally.
  def handle_cast({:work_for, duration}, state) do
    :timer.sleep(duration)
    {:stop, :normal, state}
  end
end
