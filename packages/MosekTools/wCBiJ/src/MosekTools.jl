module MosekTools

import MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities
using Mosek

using Compat # for findall

include("LinkedInts.jl")

const DEBUG = false

struct MosekSolution
    whichsol :: Soltype
    solsta   :: Solsta
    prosta   :: Prosta

    xxstatus :: Vector{Stakey}
    xx       :: Vector{Float64}
    barxj    :: Vector{Vector{Float64}}
    slx      :: Vector{Float64}
    sux      :: Vector{Float64}
    snx      :: Vector{Float64}

    cstatus  :: Vector{Stakey}
    xc       :: Vector{Float64}
    slc      :: Vector{Float64}
    suc      :: Vector{Float64}
    y        :: Vector{Float64}
end

@enum VariableType Undecided Deleted ScalarVariable MatrixVariable

struct ColumnIndex
    value::Int32
end

struct ColumnIndices
    values::Vector{Int32}
end

struct MatrixIndex
    matrix::Int32
    row::Int32
    column::Int32
    function MatrixIndex(matrix::Integer, row::Integer, column::Integer)
        @assert column ≤ row
        new(matrix, row, column)
    end
end

"""
    MosekModel <: MathOptInterface.AbstractModel

Linear variables and constraint can be deleted. For some reason MOSEK
does not support deleting PSD variables.

Note also that adding variables and constraints will permanently add
some (currently between 1 and 3) Int64s that a `delete!` will not
remove. This ensures that Indices (Variable and constraint) that
are deleted are thereafter invalid.
"""
mutable struct MosekModel  <: MOI.AbstractOptimizer
    task :: Mosek.MSKtask
    ## Options passed in `Mosek.Optimizer` that are used to create a new task
    ## in `MOI.empty!`:
    # Should Mosek output be ignored or printed ?
    be_quiet :: Bool
    # Integer parameters, i.e. parameters starting with `MSK_IPAR_`
    ipars :: Dict{String, Int32}
    # Floating point parameters, i.e. parameters starting with `MSK_DPAR_`
    dpars :: Dict{String, Float64}
    # String parameters, i.e. parameters starting with `MSK_SPAR_`
    spars :: Dict{String, AbstractString}

    """
    Number of variables explicitly created by user
    """
    publicnumvar :: Int

    has_variable_names::Bool
    constrnames :: Dict{String, Vector{MOI.ConstraintIndex}}
    # Mosek only support names for `MOI.ScalarAffineFunction` so we need a
    # fallback for `SingleVariable` and `VectorOfVariables`.
    con_to_name :: Dict{MOI.ConstraintIndex, String}

    x_type::Vector{VariableType}
    # For each MOI index of variables, gives the flags of constraints present
    # The SingleVariable constraints added cannot just be inferred from getvartype
    # and getvarbound so we need to keep them here so implement `MOI.is_valid`
    x_constraints::Vector{UInt8}

    """
        The total length of `x_block` matches the number of variables in
    the underlying task, and the number of blocks corresponds to the
    number variables allocated in the Model.
    """
    x_block::LinkedInts

    """
    One entry per scalar variable in the task indicating in which semidefinite
    block it is and at which index.
    MOI index -> MatrixIndex
    """
    x_sd::Vector{MatrixIndex}

    sd_dim::Vector{Int}

    ###########################
    """
    One scalar entry per constraint in the underlying task. One block
    per constraint allocated in the Model.
    """
    c_block :: LinkedInts

    ###########################
    trm :: Union{Nothing, Rescode}
    solutions :: Vector{MosekSolution}

    ###########################
    """
    Indicating whether the objective sense is MOI.FEASIBILITY_SENSE. It is
    encoded as a MOI.MIN_SENSE with a zero objective internally but this allows
    MOI.get(::MosekModel, ::ObjectiveSense) to still return the right value
    """
    feasibility :: Bool

    fallback :: Union{String, Nothing}
end

struct IntegerParameter <: MOI.AbstractOptimizerAttribute
    name::String
end
function MOI.set(m::MosekModel, p::IntegerParameter, value::Integer)
    m.ipars[p.name] = value
    Mosek.putnaintparam(m.task, p.name, value)
end
function MOI.get(m::MosekModel, p::IntegerParameter)
    Mosek.getnaintparam(m.task, p.name)
end

struct DoubleParameter <: MOI.AbstractOptimizerAttribute
    name::String
end
function MOI.set(m::MosekModel, p::DoubleParameter, value::AbstractFloat)
    m.dpars[p.name] = value
    Mosek.putnadouparam(m.task, p.name, value)
end
function MOI.get(m::MosekModel, p::DoubleParameter)
    Mosek.getnadouparam(m.task, p.name)
end

struct StringParameter <: MOI.AbstractOptimizerAttribute
    name::String
end
function MOI.set(m::MosekModel, p::StringParameter, value::AbstractString)
    m.spars[p.name] = value
    Mosek.putnastrparam(m.task, p.name, value)
end
function MOI.get(m::MosekModel, p::StringParameter)
    Mosek.getnastrparam(m.task, p.name)
end

struct Parameter <: MOI.AbstractOptimizerAttribute
    name::String
end
function MOI.set(m::MosekModel, p::Parameter, value)
    if p.name == "QUIET"
        if m.be_quiet != convert(Bool, value)
            m.be_quiet = !m.be_quiet
            if m.be_quiet
                Mosek.putstreamfunc(m.task, Mosek.MSK_STREAM_LOG,
                                    m -> begin end)
            else
                Mosek.putstreamfunc(m.task, Mosek.MSK_STREAM_LOG,
                                    m -> print(m))
            end
        end
    elseif p.name == "fallback"
        m.fallback = value
    else
        if startswith(p.name, "MSK_IPAR_")
            par = IntegerParameter(p.name)
        elseif startswith(p.name, "MSK_DPAR_")
            par = DoubleParameter(p.name)
        elseif startswith(p.name, "MSK_SPAR_")
            par = StringParameter(p.name)
        elseif isa(val, Integer)
            par = IntegerParameter("MSK_IPAR_" * p.name)
        elseif isa(val, AbstractFloat)
            par = DoubleParameter("MSK_DPAR_" * p.name)
        elseif isa(val, AbstractString)
            par = StringParameter("MSK_SPAR_" * p.name)
        else
            error("Value $val for parameter $option has unrecognized type")
        end
        MOI.set(m, par, value)
    end
end

function MOI.set(model::MosekModel, ::MOI.Silent, value::Bool)
    MOI.set(model, Parameter("QUIET"), value)
end

export Mosek
function Mosek.Optimizer(; kws...)
    model = MosekModel(maketask(), # task
                       false, # be_quiet
                       Dict{String, Int32}(), # ipars
                       Dict{String, Float64}(), # dpars
                       Dict{String, AbstractString}(), # spars
                       0, # public numvar
                       false, # has_variable_names
                       Dict{String, Vector{MOI.ConstraintIndex}}(), # constrnames
                       Dict{MOI.ConstraintIndex, String}(), # con_to_name
                       VariableType[], # x_type
                       UInt8[], # x_constraints
                       LinkedInts(),# x_block
                       MatrixIndex[], # x_sd
                       Int[], # sd_dim
                       LinkedInts(), # c_block
                       nothing,# trm
                       MosekSolution[],
                       true, # feasibility_sense
                       nothing)
    Mosek.putstreamfunc(model.task, Mosek.MSK_STREAM_LOG, m -> print(m))
    for (option, value) in kws
        MOI.set(model, Parameter(string(option)), value)
    end
    return model
end

function matrix_solution(m::MosekModel, sol)
    return Vector{Float64}[getbarxj(m.task, sol, j) for j in 1:length(m.sd_dim)]
end

function MOI.optimize!(m::MosekModel)
    m.trm = if m.fallback == nothing; optimize(m.task) else optimize(m.task,m.fallback) end
    m.solutions = MosekSolution[]
    if solutiondef(m.task,MSK_SOL_ITG)
        push!(m.solutions,
              MosekSolution(MSK_SOL_ITG,
                            getsolsta(m.task, MSK_SOL_ITG),
                            getprosta(m.task, MSK_SOL_ITG),
                            getskx(m.task, MSK_SOL_ITG),
                            getxx(m.task, MSK_SOL_ITG),
                            matrix_solution(m, MSK_SOL_ITG),
                            Float64[],
                            Float64[],
                            Float64[],
                            getskc(m.task, MSK_SOL_ITG),
                            getxc(m.task, MSK_SOL_ITG),
                            Float64[],
                            Float64[],
                            Float64[]))
    end
    if solutiondef(m.task,MSK_SOL_BAS)
        push!(m.solutions,
              MosekSolution(MSK_SOL_BAS,
                            getsolsta(m.task,MSK_SOL_BAS),
                            getprosta(m.task,MSK_SOL_BAS),
                            getskx(m.task,MSK_SOL_BAS),
                            getxx(m.task,MSK_SOL_BAS),
                            matrix_solution(m, MSK_SOL_BAS),
                            getslx(m.task,MSK_SOL_BAS),
                            getsux(m.task,MSK_SOL_BAS),
                            Float64[],
                            getskc(m.task,MSK_SOL_BAS),
                            getxc(m.task,MSK_SOL_BAS),
                            getslc(m.task,MSK_SOL_BAS),
                            getsuc(m.task,MSK_SOL_BAS),
                            gety(m.task,MSK_SOL_BAS)))
    end
    if solutiondef(m.task,MSK_SOL_ITR)
        push!(m.solutions,
              MosekSolution(MSK_SOL_ITR,
                            getsolsta(m.task,MSK_SOL_ITR),
                            getprosta(m.task,MSK_SOL_ITR),
                            getskx(m.task,MSK_SOL_ITR),
                            getxx(m.task,MSK_SOL_ITR),
                            matrix_solution(m, MSK_SOL_ITR),
                            getslx(m.task,MSK_SOL_ITR),
                            getsux(m.task,MSK_SOL_ITR),
                            getsnx(m.task,MSK_SOL_ITR),
                            getskc(m.task,MSK_SOL_ITR),
                            getxc(m.task,MSK_SOL_ITR),
                            getslc(m.task,MSK_SOL_ITR),
                            getsuc(m.task,MSK_SOL_ITR),
                            gety(m.task,MSK_SOL_ITR)))
    end
end

MOI.supports(::MosekModel, ::MOI.Name) = true
function MOI.set(m::MosekModel, ::MOI.Name, name::String)
    puttaskname(m.task, name)
end
function MOI.get(m::MosekModel, ::MOI.Name)
    return gettaskname(m.task)
end
function MOI.get(m::MosekModel, ::MOI.ListOfModelAttributesSet)
    set = MOI.AbstractModelAttribute[]
    if !m.feasibility
        push!(set, MOI.ObjectiveSense())
        push!(set, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    end
    set = [MOI.ObjectiveSense(), MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}()]
    if !isempty(MOI.get(m, MOI.Name()))
        push!(set, MOI.Name())
    end
    return set
end

function MOI.is_empty(m::MosekModel)
    getnumvar(m.task) == 0 && getnumcon(m.task) == 0 && getnumcone(m.task) == 0 && getnumbarvar(m.task) == 0
end

function MOI.empty!(model::MosekModel)
    model.task               = maketask()
    for (name, value) in model.ipars
        Mosek.putnaintparam(model.task, name, value)
    end
    for (name, value) in model.dpars
        Mosek.putnadouparam(model.task, name, value)
    end
    for (name, value) in model.spars
        Mosek.putnastrparam(model.task, name, value)
    end
    if !model.be_quiet
        Mosek.putstreamfunc(model.task, Mosek.MSK_STREAM_LOG, m -> print(m))
    end
    model.publicnumvar       = 0
    model.has_variable_names = false
    model.constrnames        = Dict{String, Vector{MOI.ConstraintIndex}}()
    model.con_to_name        = Dict{MOI.ConstraintIndex, String}()
    model.x_type             = VariableType[]
    model.x_constraints      = UInt8[]
    model.x_block            = LinkedInts()
    model.x_sd               = MatrixIndex[]
    model.sd_dim             = Int[]
    model.c_block            = LinkedInts()
    model.trm                = nothing
    model.solutions          = MosekSolution[]
    model.feasibility        = true
end

MOI.get(::MosekModel, ::MOI.SolverName) = "Mosek"

MOIU.supports_default_copy_to(::MosekModel, copy_names::Bool) = true
function MOI.copy_to(dest::MosekModel, src::MOI.ModelLike; kws...)
    return MOIU.automatic_copy_to(dest, src; kws...)
end

function MOI.write_to_file(m::MosekModel, filename :: String)
    putintparam(m.task,MSK_IPAR_OPF_WRITE_SOLUTIONS, MSK_ON)
    writedata(m.task,filename)
end

# For linear objectives we accept:
# EITER affine left-hand side and ranged, unbounded, half-open, fixed (equality), PSD or SOC domains
# OR affine and quadratic left-hand side, and ranged, unbounded, half-open, fixed (equality) domains (quadratic constraints must be unbounded or half-open)
#
# For non-quadratic problems we allow binary and integer variables (but not constraints)
#function supportsconstraints(m::MosekSolver, constraint_types) :: Bool
#    for (fun,dom) in constraint_types
#        if  fun in [MOI.ScalarAffineFunction{Float64},
#                    MOI.SingleVariable,
#                    MOI.VectorOfVariables] &&
#            dom in [MOI.GreaterThan{Float64},
#                    MOI.LessThan{Float64},
#                    MOI.EqualTo{Float64},
#                    MOI.Interval{Float64},
#                    MOI.SecondOrderCone,
#                    MOI.RotatedSecondOrderCone,
#                    MOI.PositiveSemidefiniteConeTriangle,
#                    MOI.PositiveSemidefiniteConeScaled ]
#            # ok
#        elseif dom in [MOI.ZeroOne,
#                       MOI.Integer] &&
#                           fun in [MOI.SingleVariable,
#                                   MOI.VectorOfVariables]
#            # ok
#        else
#            return false
#        end
#    end
#    true
#end

ref2id(vi::MOI.VariableIndex)::Int = vi.value
ref2id(ci::MOI.ConstraintIndex)::Int = ci.value

include("objective.jl")
include("variable.jl")
include("constraint.jl")
include("attributes.jl")


export MosekModel


end # module
