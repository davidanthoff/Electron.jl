using Electron
using URIParser
using Base.Test

@testset "Electron" begin

w = Window(URI("file://test.html"))

a = applications()[1]

@test isa(w, Window)

@test length(applications()) == 1
@test length(windows()) == 1

res = run(w, "Math.log(Math.exp(1))")

@test res==1

res = run(a, "Math.log(Math.exp(1))")

@test res ==1

close(w)

w2 = Window(URI("file://test.html"))

close(a)

sleep(1)

w3 = Window(Dict("url" => string(URI("file://test.html"))))

w4 = Window(URI("file://test.html"), options=Dict("title" => "Window title"))

w5 = Window("<body></body>", options=Dict("title" => "Window title"))

close(w3)

end
