__precompile__(true)

module NLSolversBase

using DiffEqDiffTools, ForwardDiff, Calculus, DiffResults
import Distributed: clear!
export AbstractObjective,
       NonDifferentiable,
       OnceDifferentiable,
       TwiceDifferentiable,
       TwiceDifferentiableHV,
       value,
       value!,
       value_gradient!,
       value_jacobian!,
       gradient,
       gradient!,
       jacobian,
       jacobian!,
       hessian,
       hessian!,
       value!!,
       value_gradient!!,
       value_jacobian!!,
       hessian!!,
       hv_product,
       hv_product!,
       only_fg!,
       only_fgh!,
       only_fj!,
       only_fg,
       only_fj,
       only_g_and_fg,
       only_j_and_fj,
       clear!,
       f_calls,
       g_calls,
       h_calls,
       hv_calls

export AbstractConstraints, OnceDifferentiableConstraints,
    TwiceDifferentiableConstraints, ConstraintBounds

function diffeqdiff_fdtype(autodiff)
    if autodiff == :finiteforward
        fdtype = Val{:forward}
    elseif autodiff == :finitecomplex
        fdtype = Val{:complex}
    elseif any(autodiff .== (:finite, :central, :finitecentral))
        fdtype = Val{:central}
    end
    fdtype
end

is_finitediff(autodiff) = autodiff ∈ (:central, :finite, :finiteforward, :finitecomplex)
is_forwarddiff(autodiff) = autodiff ∈ (:forward, :forwarddiff, true)

x_of_nans(x) = fill!(similar(x), eltype(x)(NaN))

include("objective_types/inplace_factory.jl")
include("objective_types/abstract.jl")
include("objective_types/nondifferentiable.jl")
include("objective_types/oncedifferentiable.jl")
include("objective_types/twicedifferentiable.jl")
include("objective_types/twicedifferentiablehv.jl")
include("objective_types/incomplete.jl")
include("objective_types/constraints.jl")
include("interface.jl")

end # module
