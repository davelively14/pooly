defmodule Pooly do
  use Application

  # Called by default when included in mix.exs.
  def start(_type, _args) do
    pool_config = [mfa: {SampleWorker, :start_link, []}, size: 5]
    start_pool(pool_config)
  end

  def start_pool(pool_config) do
    Pooly.Supervisor.start_link(pool_config)
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
