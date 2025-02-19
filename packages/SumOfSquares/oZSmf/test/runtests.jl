using Compat
using Compat.Test
using Compat.LinearAlgebra
using Compat.SparseArrays

using MultivariatePolynomials

# Taken from JuMP/test/solvers.jl
function try_import(name::Symbol)
    try
        @eval import $name
        return true
    catch e
        return false
    end
end

if try_import(:DynamicPolynomials)
    import DynamicPolynomials.@polyvar
else
    if try_import(:TypedPolynomials)
        import TypedPolynomials.@polyvar
    else
        error("No polynomial implementation installed : Please install TypedPolynomials or DynamicPolynomials")
    end
end

using JuMP
using SumOfSquares

include("matpoly.jl")

include("variable.jl")
include("constraint.jl")

include("solvers.jl")

include("certificate.jl")

include("motzkin.jl")

# SOSTools demos
include("sospoly.jl")
include("lyapunov.jl")
include("sosdemo3.jl")
include("sosdemo4.jl")
include("sosdemo5.jl")
include("sosdemo6.jl")
include("domain.jl")
include("sosmatrix.jl")
include("equalitypolyconstr.jl")
include("dsos.jl")
include("extract.jl")
