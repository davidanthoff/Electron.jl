using Electron
using URIs
using FilePaths
using Test

Electron.prep_test_env()

@testset "Electron" begin

    @testset "Core" begin

        @test pwd() == @__DIR__

        testpagepath = joinpath(@__PATH__, p"test.html")

        w = Window(URI(testpagepath))

        a = applications()[1]

        @test isa(w, Window)

        @test length(applications()) == 1
        @test length(windows(a)) == 1

        res = run(w, "Math.log(Math.exp(1))")

        @test res == 1

        @test_throws ErrorException run(w, "syntaxerror")

        res = run(a, "Math.log(Math.exp(1))")

        @test res == 1

        close(w)
        @test length(applications()) == 1
        @test isempty(windows(a))

        w2 = Window(joinpath(@__PATH__, p"test.html"))

        toggle_devtools(w2)

        close(a)
        @test length(applications()) == 1
        @test length(windows(a)) == 0

        sleep(1)
        @test isempty(applications())
        @test isempty(windows(a))

        w3 = Window(Dict("url" => string(URI(testpagepath))))

        w4 = Window(URI(testpagepath), options=Dict("title" => "Window title"))

        w5 = Window("<body></body>", options=Dict("title" => "Window title"))

        a2 = applications()[1]

        w6 = Window(a2, "<body></body>", options=Dict("title" => "Window title"))

        w7 = Window(a2)

        run(w7, "sendMessageToJulia('foo')")

        @test take!(msgchannel(w7)) == "foo"

        load(w7, "<body>bar</body>")

        run(w7, "sendMessageToJulia(window.document.documentElement.innerHTML)")

        @test occursin("bar", take!(msgchannel(w7)))

        load(w7, joinpath(@__PATH__, p"test.html"))
        load(w7, URI(joinpath(@__PATH__, p"test.html")))

        close(w7)

        close(w3)
        close(w4)
        close(w5)
        close(w6)
        close(a2)

    end # testset "Core"

    @testset "Application options" begin
        # Test that Application constructor works with the rationalized interface
        # Note: We can't easily test the actual command line flags without deeper introspection,
        # but we can verify the Application constructor accepts the parameters

        # Test default behavior (sandbox=false by default)
        a1 = Application()
        @test isa(a1, Electron.Application)
        close(a1)

        # Test explicit sandbox=false
        a2 = Application(sandbox=false)
        @test isa(a2, Electron.Application)
        close(a2)

        # Test explicit sandbox=true
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
            a3 = Application(sandbox=true, verbose=true)
            @test isa(a3, Electron.Application)
            close(a3)
        end

        # Test with additional electron args
        a4 = Application(additional_electron_args=["--disable-gpu"])
        @test isa(a4, Electron.Application)
        close(a4)

        # Test with custom main.js (using the default one)
        a5 = Application(mainjs=normpath(String(Electron.MAIN_JS)))
        @test isa(a5, Electron.Application)
        close(a5)

    end

    @testset "ElectronAPI" begin
        win = Window()

        @test (ElectronAPI.setBackgroundColor(win, "#000"); true)
        @test ElectronAPI.isFocused(win) isa Bool

        bounds = ElectronAPI.getBounds(win)
        boundskeys = ["width", "height", "x", "y"]
        @test Set(boundskeys) <= Set(keys(bounds))
        @test all(isa.(get.(Ref(bounds), boundskeys, nothing), Real))

        close(win)
    end

    for app in applications()
        close(app)
    end

end