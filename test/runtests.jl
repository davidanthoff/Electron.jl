using Electron
using URIParser
using Test

@testset "Electron" begin

@testset "local URI" begin
    dir = pwd(URI)
    @test unescape(dir.path) == join(push!(split(pwd(), Base.Filesystem.path_separator_re), ""), "/")
    @test dir.query == dir.fragment == dir.host == ""
    @test string(dir) == "file://$(dir.path)"

    __dirname = @__DIR__
    dir = Electron.URI_file(__dirname, "")
    @test_skip URI(dir, path = dir.path * "test.html", query = "a", fragment = "b") ==
        Electron.@LOCAL("test.html?a#b") ==
        Electron.@LOCAL(begin; "test.html?a#b"; end) ==
        Electron.URI_file(__dirname, "test.html?a#b")
end


@testset "Core" begin

w = Window(URI("file://test.html"))

a = applications()[1]

@test isa(w, Window)

@test length(applications()) == 1
@test length(windows(a)) == 1

res = run(w, "Math.log(Math.exp(1))")

@test res == 1

res = run(a, "Math.log(Math.exp(1))")

@test res ==1

close(w)
@test length(applications()) == 1
@test isempty(windows(a)) == 1

w2 = Window(URI("file://test.html"))

toggle_devtools(w2)

close(a)
@test length(applications()) == 1
@test length(windows(a)) == 0

sleep(1)
@test isempty(applications())
@test isempty(windows(a))

w3 = Window(Dict("url" => string(URI("file://test.html"))))

w4 = Window(URI("file://test.html"), options=Dict("title" => "Window title"))

w5 = Window("<body></body>", options=Dict("title" => "Window title"))

a2 = applications()[1]

w6 = Window(a2, "<body></body>", options=Dict("title" => "Window title"))

w7 = Window(a2)

run(w7, "sendMessageToJulia('foo')")

@test take!(msgchannel(w7)) == "foo"

load(w7, "<body>bar</body>")

run(w7, "sendMessageToJulia(window.document.documentElement.innerHTML)")

@test occursin("bar", take!(msgchannel(w7)))

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

close(w7)

close(w3)
close(w4)
close(w5)
close(w6)
close(a2)

end # testset "Electron"

end