#!/usr/bin/env julia

using Pkg
haskey(Pkg.installed(), "NarrativeTest") || Pkg.clone("https://github.com/rbt-lang/NarrativeTest.jl")

using DataKnots
using NarrativeTest

# Ignore the difference in the output of `print(Int)` between 32-bit and 64-bit platforms.
push!(NarrativeTest.EXPECTMAP, r"Int64" => s"Int(32|64)")

# Normalize printing of `Vector{Bool}`.
Base.show(io::IO, b::Bool) = print(io, get(io, :typeinfo, Any) === Bool ? (b ? "1" : "0") : (b ? "true" : "false"))

# Normalize `LoadError` output under 1.2.
if VERSION >= v"1.2.0-DEV"
    function Base.showerror(io::IO, ex::LoadError, bt; backtrace=true)
        print(io, "LoadError: ")
        showerror(io, ex.error, bt, backtrace=backtrace)
        print(io, "\nin expression starting at $(ex.file):$(ex.line)")
    end
end

# Normalize printing of Enum values.
if VERSION < v"1.2.0-DEV"
    Base.show(io::IO, c::DataKnots.Cardinality) =
        print(io, Symbol(c))
end

package_path(x) = relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "..", x))
args = !isempty(ARGS) ? ARGS : package_path.(["doc/src", "README.md"])
exit(!runtests(args))
