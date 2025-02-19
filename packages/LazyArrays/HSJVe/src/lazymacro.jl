# Macros for lazy broadcasting,
# based on @dawbarton  https://discourse.julialang.org/t/19641/20
# and @tkf            https://github.com/JuliaLang/julia/issues/19198#issuecomment-457967851
# and @chethega      https://github.com/JuliaLang/julia/pull/30939

using MacroTools

lazy(::Any) = throw(ArgumentError("function `lazy` exists only for its effect on broadcasting, see the macro @~"))
struct LazyCast{T}
    value::T
end
Broadcast.broadcasted(::typeof(lazy), x) = LazyCast(x)
Broadcast.materialize(x::LazyCast) = x.value


is_call(ex::Expr) =
    ex.head == :call && !startswith(String(ex.args[1]), ".")

is_dotcall(ex::Expr) =
    ex.head == :. || (ex.head == :call && startswith(String(ex.args[1]), "."))
# e.g., `f.(x, y, z)` or `x .+ y .+ z`

lazy_expr(x) = x
function lazy_expr(ex::Expr)
    if is_dotcall(ex)
        return bc_expr(ex)
    elseif is_call(ex)
        return app_expr(ex)
    else
        # TODO: Maybe better to support `a ? b : c` etc.? But how?
        return ex
    end
end

function bc_expr(ex::Expr)
    @assert is_dotcall(ex)
    return :($lazy.($(bc_expr_impl(ex))))
end

bc_expr_impl(x) = x
function bc_expr_impl(ex::Expr)
    # walk down chain of dot calls
    if is_dotcall(ex)
        return Expr(ex.head,
                    lazy_expr(ex.args[1]), # function name (`f`, `.+`, etc.)
                    bc_expr_impl.(ex.args[2:end])...) # arguments
    else
        return lazy_expr(ex)
    end
end

function app_expr(ex::Expr)
    @assert is_call(ex)
    return app_expr_impl(ex)
end

app_expr_impl(x) = x
function app_expr_impl(ex::Expr)
    # walk down chain of calls and lazy-ify them
    if is_call(ex)
        return :($applied($(app_expr_impl.(ex.args)...)))
    else
        return lazy_expr(ex)
    end
end

function checkex(ex)
    if @capture(ex, (arg__,) = val_ )
        if arg[2]==:dims
            throw(ArgumentError("@~ is capturing keyword arguments, try with `; dims = $val` instead of a comma"))
        else
            throw(ArgumentError("@~ is probably capturing capturing keyword arguments, try with ; or brackets"))
        end
    end
    if @capture(ex, (arg_,rest__) )
        throw(ArgumentError("@~ is capturing more than one expression, try $name($arg) with brackets"))
    end
    ex
end

"""
    @~ expr

Macro for creating a `Broadcasted` or `Applied` object.  Regular calls
like `f(args...)` inside `expr` are replaced with `applied(f, args...)`.
Dotted-calls like `f(args...)` inside `expr` are replaced with
`broadcasted.(f, args...)`.  Use `LazyArray(@~ expr)` if you need an
array-based interface.

```
julia> @~ A .+ B ./ 2

julia> @~ @. A + B / 2

julia> @~ A * B + C
```
"""
macro ~(ex)
    checkex(ex)
    # Expanding macro here to support, e.g., `@.`
    esc(:($instantiate($(lazy_expr(macroexpand(__module__, ex))))))
end
