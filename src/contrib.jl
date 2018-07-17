# This file contains useful utilities that really should be part of other
# packages. We keep them here for now, but eventually they will be moved
# somewhere else.

"""
    URI_file(base, filespec)

Construct an absolute URI to `filespec` relative to `base`.
"""
URI_file(base, filespec) = URI_file(base, URI("file:///$filespec"))
function URI_file(base, filespec::URI)
    base = join(map(URIParser.escape, split(base, Base.Filesystem.path_separator_re)), "/")
    return URI(filespec, path = base * filespec.path)
end

"""
    pwd(URI)

Return `pwd()` as a `URI` resource.
"""
Base.pwd(::Type{URI}) = URI_file(pwd(), "")

# TODO Fix for julia 0.7 and enable again
# """
#     @LOCAL(filespec)

# Construct an absolute URI to `filespec` relative to the source file containing the macro call.
# """
# macro LOCAL(filespec)
#     # v0.7: base = String(__source__.file)
#     #       filespec isa String && return URI_file(base, filespec) # can construct eagerly
#     #       return :(URI_file($base, $(esc(filespec))))
#     return :(URI_file(@__DIR__, $(esc(filespec))))
# end
