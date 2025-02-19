########################################################################
#                            GRAD RESULT                               #
########################################################################

function field_paths(tape::Tape)
    paths = Dict()
    for op in reverse(tape.ops)
        _op = op
        path = []
        while _op isa Call && _op.fn == Base.getproperty
            field_name = tape[_op.args[2]].val
            push!(path, field_name)
            _op_id = _op.args[1]
            _op = tape[_op_id]
        end
        if !isempty(path)
            struct_id = _op.id
            if !haskey(paths, struct_id)
                paths[struct_id] = Dict()
            end
            paths[struct_id][(reverse(path)...,)] = op.id
        end
    end
    return paths
end


struct GradResult
    tape::Tape
    gvars::Dict{Int, Any}  # gradient vars: argid -> gradient var
end


function GradResult(tape::Tape)
    tape.fieldpaths = field_paths(tape)
    gvars = Dict{Int,Any}()
    # struct fields
    for (argid, dct) in tape.fieldpaths
        gvars[argid] = Dict(field_path => tape.derivs[var_id]
                            for (field_path, var_id) in dct
                            if haskey(tape.derivs, var_id))  # not all fields may have derivatives
    end
    # other arguments
    struct_arg_ids = Set(keys(tape.fieldpaths))
    for op in tape
        if op isa Input && !in(op.id, struct_arg_ids)
            gvars[op.id] = tape.derivs[op.id]
        end
    end
    return GradResult(tape, gvars)
end


Base.show(io::IO, g::GradResult) = print(io, "GradResult($(length(g.gvars)))")

function Base.getindex(g::GradResult, argid::Int)
    tape = g.tape
    gvar = g.gvars[argid]
    if isa(gvar, Dict)
        return Dict(f => tape[id].val for (f, id) in gvar)
    else
        return tape[gvar].val
    end
end

Base.length(g::GradResult) = length(g.gvars)
Base.iterate(g::GradResult) = length(g) > 0 ? (g[1], 2) : nothing
Base.iterate(g::GradResult, state) = length(g) >= state ? (g[state], state + 1) : nothing


########################################################################
#                              GRAD                                    #
########################################################################

const DEBUG_STATE = Any[]


getderiv(tape::Tape, id::Int) = tape[tape.derivs[id]]
getderiv(tape::Tape, op::AbstractOp) = getderiv(tape, op.id)
setderiv!(tape::Tape, op_id::Int, grad_op_id::Int) = (tape.derivs[op_id] = grad_op_id)
setderiv!(tape::Tape, op::AbstractOp, grad_op::AbstractOp) = (tape.derivs[op.id] = grad_op.id)


Espresso.to_expr(tape::Tape, op::Call) = begin
    @assert isempty(op.kwargs) "Oops, functions with kwargs aren't supported just yet"
    Expr(:call, op.fn, [Symbol("%$i") for i in op.args]...)
end

to_unbroadcast_expr(tape::Tape, op::Call) =
    Expr(:call, tape[op.args[1]].val, [Symbol("%$i") for i in op.args[2:end]]...)


function deriv!(tape::Tape, op::AbstractOp, i::Int, dy::AbstractOp)
    ex = to_expr(tape, op)
    dep_types = [tape[arg].typ for arg in op.args]
    dex = deriv_expr(ex, dep_types, i)
    st = Dict(Symbol("%$i") => i for i in op.args)
    st[:ds] = dy.id
    ret_id = record_expr!(tape, dex; st=st)
    return tape[ret_id]
end


function deriv_broadcast!(tape::Tape, op::AbstractOp, i::Int, dy::AbstractOp)
    ex = to_unbroadcast_expr(tape, op)
    dep_eltypes = [eltype(tape[arg].typ) for arg in op.args[2:end]]
    dex = deriv_expr(ex, dep_eltypes, i-1)
    st = Dict(Symbol("%$id") => id for id in op.args)
    st[:ds] = dy.id
    ret_id = record_expr!(tape, dex; st=st, bcast=true)
    return tape[ret_id]
end


function step_back!(tape::Tape, op::Union{Call}, i::Int)
    y = op
    x = tape[op.args[i]]
    dy = getderiv(tape, y)
    # we handle broadcasting for + like normal derivatives
    # all other cases are handled by a generic bcast mechanism
    use_bcast_rules = (op.fn == broadcast) && !in(tape[op.args[1]].val, Set([+]))
    dx = try
        use_bcast_rules ? deriv_broadcast!(tape, op, i, dy) : deriv!(tape, op, i, dy)
    catch
        @error("Failed to find a derivative for $op at position $i, " *
               "current state of backpropagation saved to Yota.DEBUG_STATE")
        push!(DEBUG_STATE, (tape, op, i))
        rethrow()
    end
    if !haskey(tape.derivs, x.id)
        setderiv!(tape, x, dx)
    else
        # @warn "This branch hasn't been tested yet"
        old_dx = getderiv(tape, x)
        val = dx.val + old_dx.val
        new_dx_id = record!(tape, Call, val, +, [dx.id, old_dx.id])
        new_dx = tape[new_dx_id]
        setderiv!(tape, x, new_dx)
    end
end


"""
Backpropagate through the tape, record derivatives as new operations
"""
function back!(tape::Tape)
    # z - final variable (usually a loss)
    # y - resulting variable of current op
    # x - dependencies of y
    # dy - derivative of z w.r.t. y
    z = tape[tape.resultid]
    # using Float32 for seed since for 64-bit args it will be expanded anyway
    dy_id = record!(tape, Constant, 1.0f0)
    dy = tape[dy_id]
    # set initial derivative value
    tape.derivs[z.id] = dy.id
    for op in reverse(tape.ops[1:end-1])
        if op isa Call && op.fn != Base.getproperty
            for i=1:length(op.args)
                # backpropagate only non-constant vars
                # note that it also prevents backprop on 1st param of broadcast
                arg_op = tape[op.args[i]]
                if !isa(arg_op, Constant)
                    # println(op, " ", i)
                    step_back!(tape, op, i)
                end
            end
        end
    end
end



"""
For each input that has a derivative on this tape check if the derivative
has the same size as the input.
"""
function check_deriv_sizes(tape::Tape)
    for (var_id, grad_var_id) in tape.derivs
        var_size = size(tape[var_id].val)
        grad_var_size = size(tape[grad_var_id].val)
        if  var_size != grad_var_size
            @warn "Gradient %$grad_var_id has size $grad_var_size, " *
                "but original variable %$var_id has size $var_size"
        end
    end
end


function _grad(f::Function, args...)
    val, tape = trace(f, args...)
    # backpropagate gradients
    back!(tape)
    # consistency check
    check_deriv_sizes(tape)
    # construct GradResult object that wraps tape and provide accessors for computed derivatives
    return val, GradResult(tape)
end


const GRAD_CACHE = Dict{Any, Tape}()


"""
Find gradient of `f` w.r.t. its arguments.
Example:

    val, g = grad(sum, rand(3))

where:
  - val is the value of `f` at this point
  - g::GradResult is a collection of gradients

GradResult is indexed by argument index and contains gradients
in a format most suitable for that argument, namely:

  - for arrays: arrays of the same type and size
  - for reals: reals
  - for mutable structs: dictionary of {(:field, :path) => value} pairs.

All gradients can be applied to original variables using `update!()` function.
"""
function grad(f::Function, args...)
    # key consists of function type and type of argument (for structs) or its size
    cache_key = (f, ([isstruct(arg) ? typeof(arg) : size(arg) for arg in args]...,))
    if haskey(GRAD_CACHE, cache_key)
        tape = GRAD_CACHE[cache_key]
        val = play!(tape, args...)
        return val, GradResult(tape)
    else
        val, g = _grad(f, args...)
        compile!(g.tape)
        GRAD_CACHE[cache_key] = g.tape
        return val, g
    end
end
