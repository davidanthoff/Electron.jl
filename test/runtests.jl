using Electron
using URIParser
using Base.Test

@testset "local URI" begin
    dir = pwd(URI)
    @test unescape(dir.path) == join(push!(split(pwd(), Base.Filesystem.path_separator_re), ""), "/")
    @test dir.query == dir.fragment == dir.host == ""
    @test string(dir) == "file://$(dir.path)"

    __dirname = @__DIR__
    dir = Electron.URI_file(__dirname, "")
    @test URI(dir, path = dir.path * "test.html", query = "a", fragment = "b") ==
        Electron.@LOCAL("test.html?a#b") ==
        Electron.@LOCAL(begin; "test.html?a#b"; end) ==
        Electron.URI_file(__dirname, "test.html?a#b")
end


@testset "Electron" begin

println("A")

w = Window(URI("file://test.html"))

println("B")

a = applications()[1]

@test isa(w, Window)

@test length(applications()) == 1
@test length(windows(a)) == 1

res = run(w, "Math.log(Math.exp(1))")

println("C")

@test res == 1

res = run(a, "Math.log(Math.exp(1))")

println("D")

@test res ==1

close(w)

println("E")
@test length(applications()) == 1
@test isempty(windows(a)) == 1


w2 = Window(URI("file://test.html"))

println("F")

close(a)
@test length(applications()) == 1
@test length(windows(a)) == 0

println("G")

sleep(1)
@test isempty(applications())
@test isempty(windows(a))

println("H")

w3 = Window(Dict("url" => string(URI("file://test.html"))))

println("I")

w4 = Window(URI("file://test.html"), options=Dict("title" => "Window title"))

println("J")

w5 = Window("<body></body>", options=Dict("title" => "Window title"))

a2 = applications()[1]

w6 = Window(a2, "<body></body>", options=Dict("title" => "Window title"))

println("K")

close(w3)
println("L")
close(w4)
println("M")
close(w5)
println("N")
close(w6)
println("O")
close(a2)
println("P")

end # testset "Electron"
