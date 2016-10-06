defmodule Pooly.Server do
  use GenServer
  import Supervisor.Spec

  #######
  # API #
  #######

  def start_link(pools_config) do
    GenServer.start_link(__MODULE__, pools_config, name: __MODULE__)
  end

  # Use a dynamically constructed atom to refer to a respective pool server
  def checkout(pool_name) do
    GenServer.call(:"#{pool_name}Server", :checkout)
  end

  # Use a dynamically constructed atom to refer to a respective pool server
  def checkin(pool_name, worker_pid) do
    GenServer.cast(:"#{pool_name}Server", {:checkin, worker_pid})
  end

  # Use a dynamically constructed atom to refer to a respective pool server
  def status(pool_name) do
    GenServer.call(:"#{pool_name}Server", :status)
  end

  #############
  # Callbacks #
  #############

  # This callback is always called by GenServer.start_link. It iterates through
  # each configuration and sends :start_pool message to itself
  def init(pools_config) do
    pools_config |> Enum.each(fn(pool_config) ->
      send(self, {:start_pool, pool_config})
    end)

    {:ok, pools_config}
  end

  def handle_info({:start_pool, pool_config}, state) do
    {:ok, _pool_sup} = Supervisor.start_child(Poly.PoolsSupervisor, supervisor_spec(pool_config))

    {:noreply, state}
  end

  #####################
  # Private Functions #
  #####################

  # Helper function to return a unique Supervisor spec with the id option set
  # to the name from pool_config. Those id options have to be unique. If it's
  # not, you'll get an :already_started error.
  defp supervisor_spec(pool_config) do
    opts = [id: :"#{pool_config[:name]}Supervisor"]
    supervisor(Pooly.PoolSupervisor, [pool_config], opts)
  end
end
