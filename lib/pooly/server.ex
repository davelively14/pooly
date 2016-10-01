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
  # supervisor pid to the State structure, and calls init/3
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

  # Base case when the options list is empty. Sends a message to start the
  # worker supervisor.
  def init([], state) do
    send(self, :start_worker_supervisor)
    {:ok, state}
  end
end
