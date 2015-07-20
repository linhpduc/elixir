Code.require_file "../test_helper.exs", __DIR__

defmodule ExUnit.CaptureLogTest do
  use ExUnit.Case

  require Logger

  import ExUnit.CaptureLog

  setup_all do
    :ok = Logger.remove_backend(:console)
    on_exit(fn -> Logger.add_backend(:console, flush: true) end)
  end

  test "no output" do
    assert capture_log(fn -> end) == ""
  end

  test "assert inside" do
    group_leader = Process.group_leader()

    try do
      capture_log(fn ->
        assert false
      end)
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message == "Expected truthy, got false"
    end

    # Ensure no leakage on failures
    assert group_leader == Process.group_leader()
    refute_received {:gen_event_EXIT, _, _}
  end

  test "level aware" do
    assert capture_log([level: :warn], fn ->
      Logger.info "here"
    end) == ""
  end

  @tag timeout: 5_000
  test "capture removal on exit" do
    handlers = GenEvent.which_handlers(Logger)

    pid = spawn(fn ->
      capture_log(fn ->
        spawn_link(Kernel, :exit, [:shutdown])
        :timer.sleep(:infinity)
      end)
    end)

    # Assert the process is down then invoke capture_io
    # to trigger the ExUnit.Server, ensuring the DOWN
    # message from capture_log has been processed
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}
    ExUnit.CaptureIO.capture_io(fn -> "oops" end)

    assert GenEvent.which_handlers(Logger) == handlers
  end

  test "log tracking" do
    logged =
      assert capture_log(fn ->
        Logger.info "one"

        logged = capture_log(fn -> Logger.error "one" end)
        send(test = self(), {:nested, logged})

        Logger.warn "two"

        spawn(fn ->
          Logger.debug "three"
          send(test, :done)
        end)
        receive do: (:done -> :ok)
      end)

    assert logged =~ "[info]  one\n"
    assert logged =~ "[warn]  two\n"
    assert logged =~ "[debug] three\n"
    assert logged =~ "[error] one\n"

    receive do
      {:nested, logged} ->
        assert logged =~ "[error] one\n"
        refute logged =~ "[warn]  two\n"
    end
  end
end
