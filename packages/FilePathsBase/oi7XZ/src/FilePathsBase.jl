__precompile__()

module FilePathsBase

using Dates
using LinearAlgebra
using Printf
using UUIDs

import Base: ==
export
    # Types
    AbstractPath,
    Path,
    SystemPath,
    PosixPath,
    WindowsPath,
    Mode,
    Status,

    # Methods
    cwd,
    home,
    hasparent,
    parents,
    filename,
    extension,
    extensions,
    exists,
    isabs,
    mode,
    created,
    modified,
    relative,
    ismount,
    islink,
    cp,
    mv,
    sync,
    tmpname,
    tmpdir,
    mktmp,
    mktmpdir,
    chown,
    executable,
    readable,
    writable,
    raw,
    readpath,
    walkpath,

    # Macros
    @p_str,
    @__PATH__,
    @__FILEPATH__,

    # Constants
    READ,
    WRITE,
    EXEC


export isexecutable

const PATH_TYPES = DataType[]

function __init__()
    register(PosixPath)
    register(WindowsPath)
end

"""
    AbstractPath

Defines an abstract filesystem path.

# Properties

- `segments::Tuple{Vararg{String}}` - path segments (required)
- `root::String` - path root (defaults to "/")
- `drive::String` - path drive (defaults to "")
- `separator::String` - path separator (defaults to "/")

# Required Methods
- `T(str::String)` - A string constructor
- `FilePathsBase.ispathtype(::Type{T}, x::AbstractString) = true`
- `read(path::T)`
- `write(path::T, data)`
- `exists(path::T` - whether the path exists
- `stat(path::T)` - File status describing permissions, size and creation/modified times
- `mkdir(path::T; kwargs...)` - Create a new directory
- `rm(path::T; kwags...)` - Remove a file or directory
- `readdir(path::T)` - Scan all files and directories at a specific path level
"""
abstract type AbstractPath end  # Define the AbstractPath here to avoid circular include dependencies

"""
    register(::Type{<:AbstractPath})

Registers a new path type to support using `Path("...")` constructor and p"..." string
macro.
"""
function register(T::Type{<:AbstractPath})
    # We add the type to the beginning of our PATH_TYPES,
    # so that they can take precedence over the Posix and
    # Windows paths.
    pushfirst!(PATH_TYPES, T)
end

"""
    ispathtype(::Type{T}, x::AbstractString) where T <: AbstractPath

Return a boolean as to whether the string `x` fits the specified the path type.
"""
function ispathtype end

include("constants.jl")
include("utils.jl")
include("libc.jl")
include("mode.jl")
include("status.jl")
include("buffer.jl")
include("path.jl")
include("posix.jl")
include("windows.jl")
include("system.jl")
include("test.jl")

end # end of module
