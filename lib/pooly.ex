defmodule Pooly do
  use Application

  # Called by default when included in mix.exs.
  def start(_type, _args) do

    # Each pool gets its own configuration
    pools_config =
      [
        [name: "Pool1", mfa: {SampleWorker, :start_link, []}, size: 2],
        [name: "Pool2", mfa: {SampleWorker, :start_link, []}, size: 3],
        [name: "Pool3", mfa: {SampleWorker, :start_link, []}, size: 4],
      ]
    start_pools(pools_config)
  end

  def start_pools(pools_config) do
    Pooly.Supervisor.start_link(pools_config)
  end

  # Below is a series of functions that allow the user to interact with the
  # server without having to call Pooly.Server every time.

  def checkout do
    Pooly.Server.checkout
  end

  def checkin(worker_pid) do
    Pooly.Server.checkin(worker_pid)
  end

  def status do
    Pooly.Server.status
  end
end
