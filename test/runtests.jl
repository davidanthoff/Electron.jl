using Electron
using URIParser
using FilePaths
using Base.Test

@testset "Electron" begin

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

w2 = Window(@LOCAL("test.html"))

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

close(w3)
close(w4)
close(w5)
close(w6)
close(a2)

end # testset "Electron"
