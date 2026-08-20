@testitem "Application default options" begin
    app = Application()
    try
        @test isa(app, Electron.Application)
    finally
        app.exists && close(app)
    end
end

@testitem "Application with sandbox disabled" begin
    app = Application(sandbox=false)
    try
        @test isa(app, Electron.Application)
    finally
        app.exists && close(app)
    end
end

@testitem "Application with sandbox enabled" begin
    # Skip this test on Linux when JULIA_ELECTRON_HEADLESS is true because of this error:
    # ---
    # [2528:0710/174822.432243:FATAL:zygote_host_impl_linux.cc(128)] No usable sandbox! If you are running on
    # Ubuntu 23.10+ or another Linux distro that has disabled unprivileged user namespaces with AppArmor,
    # see https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md.
    # Otherwise see https://chromium.googlesource.com/chromium/src/+/main/docs/linux/suid_sandbox_development.md for
    # more information on developing with the (older) SUID sandbox. If you want to live dangerously and need an
    # immediate workaround, you can try using --no-sandbox.
    # ---
    if !(Sys.islinux() && Base.get_bool_env("JULIA_ELECTRON_HEADLESS", false))
        app = Application(sandbox=true, verbose=true)
        try
            @test isa(app, Electron.Application)
        finally
            app.exists && close(app)
        end
    end
end

@testitem "Application with additional electron args" begin
    app = Application(additional_electron_args=["--disable-gpu"])
    try
        @test isa(app, Electron.Application)
    finally
        app.exists && close(app)
    end
end

@testitem "Application with explicit mainjs" begin
    app = Application(mainjs=normpath(String(Electron.MAIN_JS)))
    try
        @test isa(app, Electron.Application)
    finally
        app.exists && close(app)
    end
end
