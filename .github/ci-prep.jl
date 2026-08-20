# Runs once per CI job, on every platform in the matrix, before the test items are run.
#
# Electron needs a display. The Linux runners are headless, so start an X server on :99
# here; the workflow passes DISPLAY=:99 on to the test worker processes.
if Sys.islinux()
    run(`Xvfb :99 -screen 0 1024x768x24`, wait=false)

    for _ in 1:100
        isfile("/tmp/.X99-lock") && break
        sleep(0.1)
    end

    isfile("/tmp/.X99-lock") || error("Xvfb did not come up on display :99.")
end
