@testsnippet ElectronTestHelpers begin
    # Electron.jl removes closed windows and closed applications from its global
    # bookkeeping asynchronously, once the notification arrives from the Electron
    # process, so anything asserting on those counts has to wait for that to happen.
    wait_until(f, timeout=30.0) = timedwait(f, timeout) === :ok

    # A test process is reused across test items, so an application closed by an
    # earlier item may still be listed when this one starts. Wait for a clean slate.
    function wait_for_no_applications()
        wait_until(() -> isempty(applications())) ||
            error("Electron applications from an earlier test item are still running.")
    end
end
