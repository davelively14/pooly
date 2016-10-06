defmodule Pooly do
  use Application

  # Called by default when included in mix.exs.
  def start(_type, _args) do

    # Each pool gets its own configuration
    pools_config =
      [
        [name: "Pool1", mfa: {SampleWorker, :start_link, []}, size: 2, max_overflow: 3],
        [name: "Pool2", mfa: {SampleWorker, :start_link, []}, size: 3, max_overflow: 0],
        [name: "Pool3", mfa: {SampleWorker, :start_link, []}, size: 4, max_overflow: 0],
      ]
    start_pools(pools_config)
  end

  def start_pools(pools_config) do
    Pooly.Supervisor.start_link(pools_config)
  end

  # Below is a series of functions that allow the user to interact with the
  # server without having to call Pooly.Server every time.

  def checkout(pool_name) do
    Pooly.Server.checkout(pool_name)
  end

  def checkin(pool_name, worker_pid) do
    Pooly.Server.checkin(pool_name, worker_pid)
  end

  def status(pool_name) do
    Pooly.Server.status(pool_name)
  end
end
