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
