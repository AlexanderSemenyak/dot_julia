# For generating symbols that work as dataframe column names; symbols
# generated by gensym() don't work for this.
global _rvnum = 0

function _make_rvname(name)
    global _rvnum += 1
    return Symbol("$(name)!$(_rvnum)")
end

function _make_dims(args)
    dims = Vector{Any}()
    for arg in args
        # println("Arg: $arg")

        if @capture(arg, i_Int)  # scalar (must be integer)
            # println("arg is Int")
            dim = i

        elseif @capture(arg, first_Int:last_)   # last can be an int or 'end', which is converted to 0
            # println("arg is range")
            last = last == :end ? 0 : last
            dim = :($first:$last)

        elseif @capture(arg, first_Int:step_:last_)
            # println("arg is step range")
            last = last == :end ? 0 : last
            dim = :($first:$step:$last)

        elseif @capture(arg, s_Symbol)
            if arg == :(:)
                # println("arg is Colon")
                dim = Colon()
            else
                # println("arg is Symbol")
                dim = :($(QuoteNode(s)))
            end

        elseif @capture(arg, s_String)
            dim = s

        elseif isa(arg, Expr) && arg.head == :tuple  # tuple of Strings/Symbols (@capture didn't work...)
            argtype = typeof(arg.args[1])            # ensure all are same type as first element
            if ! isempty(filter(s -> typeof(s) != argtype, arg.args))
                error("A parameter dimension tuple must be all Strings or all Symbols (got $arg)")
            end
            dim = :(convert(Vector{$argtype}, $(arg.args)))

        else
            error("Unrecognized stochastic parameter specification: $arg")
        end
        push!(dims, dim)
    end
    # println("dims = $dims")
    return dims
end

macro defsim(expr)
    let # to make vars local to each macro invocation
        local _rvs        = []
        local _transforms = []
        local _saves      = []
        local _sim_args  = Dict{Symbol, Any}()

        simdatatype = nothing

        # distilled into a function since it's called from two branches below
        function saverv(rvname, distname, distargs)
            expr = :(RandomVariable($(QuoteNode(rvname)), $distname($(distargs...))))
            push!(_rvs, esc(expr))
        end

        @capture(expr, elements__)
        for elt in elements
            # Meta.show_sexpr(elt)
            # println("")
            # e.g.,  rv(name1) = Normal(10, 3)
            if @capture(elt, rv(rvname_) = distname_(distargs__))
                saverv(rvname, distname, distargs)

            elseif @capture(elt, save(vars__))
                for var in vars
                    # println("var: $var")
                    if @capture(var, comp_.datum_)
                        expr = :($(QuoteNode(comp)), $(QuoteNode(datum)))
                        push!(_saves, esc(expr))
                    else
                        error("Save arg spec must be of the form comp_name.datum_name; got ($var)")
                    end
                end

            # handle vector of distributions
            elseif @capture(elt, extvar_ = [items__])
                for pair in items
                    if (@capture(pair, [dims__] => distname_(distargs__)) ||
                        @capture(pair,     dim_ => distname_(distargs__)))

                        dims = _make_dims(dims === nothing ? [dim] : dims)

                        rvname = _make_rvname(extvar)
                        saverv(rvname, distname, distargs)

                        expr = :(TransformSpec($(QuoteNode(extvar)), :(=), $(QuoteNode(rvname)), [$(dims...)]))
                        push!(_transforms, esc(expr))
                    end
                end

            # e.g., ext_var5[2010:2050, :] *= name2
            elseif (@capture(elt, extvar_  = rvname_Symbol) ||
                    @capture(elt, extvar_ += rvname_Symbol) ||
                    @capture(elt, extvar_ *= rvname_Symbol) ||
                    @capture(elt, extvar_  = distname_(distargs__)) ||
                    @capture(elt, extvar_ += distname_(distargs__)) ||
                    @capture(elt, extvar_ *= distname_(distargs__)))

                # For "anonymous" RVs, e.g., ext_var2[2010:2100, :] *= Uniform(0.8, 1.2), we
                # gensym a name based on the external var name and process it as a named RV.
                if rvname === nothing
                    param_name = @capture(extvar, name_[args__]) ? name : extvar
                    rvname = _make_rvname(param_name)
                    saverv(rvname, distname, distargs)
                end

                op = elt.head
                if @capture(extvar, name_[args__])
                    # println("Ref:  $name, $args")        
                    # Meta.show_sexpr(extvar)
                    # println("")

                    # if extvar.head == :ref, extvar.args must be one of:
                    # - a scalar value, e.g., name[2050] => (:ref, :name, 2050)
                    #   convert to tuple of dimension specifiers (:name, 2050)
                    # - a slice expression, e.g., name[2010:2050] => (:ref, :name, (:(:), 2010, 2050))
                    #   convert to (:name, 2010:2050) [convert it to actual UnitRange instance]
                    # - a tuple of symbols, e.g., name[(US, CHI)] => (:ref, :name, (:tuple, :US, :CHI))
                    #   convert to (:name, (:US, :CHI))
                    # - combinations of these, e.g., name[2010:2050, (US, CHI)] => (:ref, :name, (:(:), 2010, 2050), (:tuple, :US, :CHI))
                    #   convert to (:name, 2010:2050, (:US, :CHI))

                    dims = _make_dims(args)
                    expr = :(TransformSpec($(QuoteNode(name)), $(QuoteNode(op)), $(QuoteNode(rvname)), [$(dims...)]))
                else
                    expr = :(TransformSpec($(QuoteNode(extvar)), $(QuoteNode(op)), $(QuoteNode(rvname))))
                end
                push!(_transforms, esc(expr))

            elseif @capture(elt, sampling(simdatatype_, simargs__))
                # General method for setting an SA method's required parameters
                for arg in simargs
                    if !@capture(arg, name_=value_)
                        error("simargs must be given as keyword arguments (got $simargs)")
                    end
                    _sim_args[name] = __module__.eval(value)
                end
            else
                error("Unrecognized expression '$elt' in @defsim")
            end
        end

        # set default
        simdatatype = (simdatatype == nothing) ? nameof(MCSData) : simdatatype
    
        # call constructor on given args
        data = :($simdatatype(; $(_sim_args)...))

        # TBD: need to generalize this to support other methods
        return :(Simulation{$simdatatype}(
                    [$(_rvs...)],
                    [$(_transforms...)],  
                    Tuple{Symbol, Symbol}[$(_saves...)],
                    $data))
    end
end

#
# Simulation update methods
#
function _update_nt_type!(sim::Simulation{T}) where T <: AbstractSimulationData
    names = (keys(sim.rvdict)...,)
    types = [eltype(fld) for fld in values(sim.rvdict)]
    sim.nt_type = NamedTuple{names, Tuple{types...}}
    nothing
end

"""
    deleteRV!(sim::Simulation, name::Symbol)

Delete the random variable `name` from the Simulation `sim`.
Transformations using this RV are deleted, and the Simulation's
NamedTuple type is updated to reflect the dropped RV.
"""
function deleteRV!(sim::Simulation, name::Symbol)
    deleteTransform!(sim, name)
    delete!(sim.rvdict, name)
    _update_nt_type!(sim)
end

"""
    addRV!(sim::Simulation, rv::RandomVariable)

Add random variable definition `rv` to Simulation `sim`. The 
Simulation's NamedTuple type is updated to include the RV.
"""
function addRV!(sim::Simulation, rv::RandomVariable)
    name = rv.name
    haskey(sim.rvdict, name) && error("Simulation already has RV :$name. Use replaceRV! to replace it.")
    sim.rvdict[name] = rv
    _update_nt_type!(sim)
end

"""
    addRV!(sim::Simulation, name::Symbol, dist::Distribution)

Add random variable definition `rv` to Simulation `sim`. The 
Simulation's NamedTuple type is updated to include the RV.
"""
addRV!(sim::Simulation, name::Symbol, dist::Distribution) = addRV!(sim, RandomVariable(name, dist))

"""
    replaceRV!(sim::Simulation, rv::RandomVariable)

Replace the RV with the given `rv`s name in the Simulation Sim with
`rv` and update the Simulation's NamedTuple type accordingly.
"""
function replaceRV!(sim::Simulation, rv::RandomVariable)
    sim.rvdict[rv.name] = rv
    _update_nt_type!(sim)
end

"""
    replaceRV!(sim::Simulation, name::Symbol, dist::Distribution)

Replace the with name `name` in the Simulation Sim with a new RV
with `name` and distribution `dist`. Update the Simulation's NamedTuple
type accordingly.
"""
replaceRV!(sim::Simulation, name::Symbol, dist::Distribution) = replaceRV!(sim, RandomVariable(name, dist))

"""
    deleteTransform!(sim::Simulation, name::Symbol)

Delete all data transformations--i.e., replacement, addition or multiplication 
of original data values with values drawn from the RV named `name`. Update the 
Simulation's NamedTuple type accordingly.
"""
function deleteTransform!(sim::Simulation, name::Symbol)
    pos = findall(t -> t.rvname == name, sim.translist)
    deleteat!(sim.translist, pos)    
    _update_nt_type!(sim)
end

"""
    addTransform!(sim::Simulation, t::TransformSpec)

Add the data transformation `t` to the Simulation `sim`, and update the
Simulation's NamedTuple type. The TransformSpec `t` must refer to an 
existing RV.
"""
function addTransform!(sim::Simulation, t::TransformSpec)
    push!(sim.translist, t)
    _update_nt_type!(sim)
end

"""
    addTransform!(sim::Simulation, paramname::Symbol, op::Symbol, rvname::Symbol, dims::Vector{T}=[]) where T

Create a new TransformSpec based on `paramname`, `op`, `rvname` and `dims` to the 
Simulation `sim`, and update the Simulation's NamedTuple type. The symbol `rvname` must
refer to an existing RV, and `paramname` must refer to an existing parameter. If `dims` are
provided, these must be legal subscripts of `paramname`. Op must be one of :+=, :*=, or :(=).
"""
function addTransform!(sim::Simulation, paramname::Symbol, op::Symbol, rvname::Symbol, dims::Vector{T}=[]) where T
    addTransform!(sim, TransformSpec(paramname, op, rvname, dims))
end

"""
    deleteSave!(sim::Simulation, key::Tuple{Symbol, Symbol})

Delete from Simulation `sim` a "save" instruction for the given `key`, comprising
component `comp_name` and parameter or variable `datum_name`. This result will no 
longer be saved to a CSV file at the end of the simulation.
"""
function deleteSave!(sim::Simulation, key::Tuple{Symbol, Symbol})
    pos = findall(isequal(key), sim.savelist)
    deleteat!(sim.savelist, pos)
end

"""
    deleteSave!(sim::Simulation, comp_name::Symbol, datum_name::Symbol)

Delete from Simulation `sim` a "save" instruction for component `comp_name` and parameter 
or variable `datum_name`. This result will no longer be saved to a CSV file at the end
of the simulation.
"""
deleteSave!(sim::Simulation, comp_name::Symbol, datum_name::Symbol) = deleteSave!(sim, (comp_name, datum_name))

"""
    addSave!(sim::Simulation, key::Tuple{Symbol, Symbol})

Add to Simulation `sim` a "save" instruction for the given `key`, comprising
component `comp_name` and parameter or variable `datum_name`. This result will
be saved to a CSV file at the end of the simulation.
"""
function addSave!(sim::Simulation, key::Tuple{Symbol, Symbol})
    deleteSave!(sim, key) 
    push!(sim.savelist, key)
    nothing
end

"""
    addSave!(sim::Simulation, comp_name::Symbol, datum_name::Symbol)

Add to Simulation `sim` a "save" instruction for component `comp_name` and parameter or
variable `datum_name`. This result will be saved to a CSV file at the end of the simulation.    
"""
addSave!(sim::Simulation, comp_name::Symbol, datum_name::Symbol) = addSave!(sim, (comp_name, datum_name))
