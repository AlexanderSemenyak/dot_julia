# validation of properties and code

function check_method(ctx::CompilerContext)
    # get the method
    ms = Base.methods(ctx.f, ctx.tt)
    isempty(ms)   && throw(KernelError(ctx, "no method found"))
    length(ms)!=1 && throw(KernelError(ctx, "no unique matching method"))
    m = first(ms)

    # kernels can't return values
    if ctx.kernel
        rt = Base.return_types(ctx.f, ctx.tt)[1]
        if rt != Nothing
            throw(KernelError(ctx, "kernel returns a value of type `$rt`",
                """Make sure your kernel function ends in `return`, `return nothing` or `nothing`.
                   If the returned value is of type `Union{}`, your Julia code probably throws an exception.
                   Inspect the code with `@device_code_warntype` for more details."""))
        end
    end

    return
end

function check_invocation(ctx::CompilerContext, entry::LLVM.Function)
    # make sure any non-isbits arguments are unused
    real_arg_i = 0
    sig = Base.signature_type(ctx.f, ctx.tt)::Type
    for (arg_i,dt) in enumerate(sig.parameters)
        isghosttype(dt) && continue
        real_arg_i += 1

        if !isbitstype(dt)
            param = parameters(entry)[real_arg_i]
            if !isempty(uses(param))
                throw(KernelError(ctx, "passing and using non-bitstype argument",
                    """Argument $arg_i to your kernel function is of type $dt.
                       That type is not isbits, and such arguments are only allowed when they are unused by the kernel."""))
            end
        end
    end

    return
end


## IR validation

const IRError = Tuple{String, StackTraces.StackTrace, Any} # kind, bt, meta

struct InvalidIRError <: Exception
    ctx::CompilerContext
    errors::Vector{IRError}
end

const RUNTIME_FUNCTION = "call to the Julia runtime"
const UNKNOWN_FUNCTION = "call to an unknown function"
const POINTER_FUNCTION = "call through a literal pointer"

function Base.showerror(io::IO, err::InvalidIRError)
    print(io, "InvalidIRError: compiling $(signature(err.ctx)) resulted in invalid LLVM IR")
    for (kind, bt, meta) in err.errors
        print(io, "\nReason: unsupported $kind")
        if meta != nothing
            if kind == RUNTIME_FUNCTION || kind == UNKNOWN_FUNCTION || kind == POINTER_FUNCTION
                print(io, " (call to ", meta, ")")
            end
        end
        Base.show_backtrace(io, bt)
    end
    return
end

# generate a pseudo-backtrace from LLVM IR instruction debug information
#
# this works by looking up the debug information of the instruction, and inspecting the call
# sites of the containing function. if there's only one, repeat the process from that call.
# finally, the debug information is converted to a Julia stack trace.
function backtrace(inst, bt = StackTraces.StackFrame[])
    name = Ref{Cstring}()
    filename = Ref{Cstring}()
    line = Ref{Cuint}()
    col = Ref{Cuint}()

    # look up the debug information from the current instruction
    depth = 0
    while LLVM.API.LLVMGetSourceLocation(LLVM.ref(inst), depth, name, filename, line, col) == 1
        frame = StackTraces.StackFrame(replace(unsafe_string(name[]), r";$"=>""),
                                       unsafe_string(filename[]), line[])
        push!(bt, frame)
        depth += 1
    end

    # move up the call chain
    f = LLVM.parent(LLVM.parent(inst))
    callers = uses(f)
    if !isempty(callers)
        # figure out the call sites of this instruction
        call_sites = unique(callers) do call
            # there could be multiple calls, originating from the same source location
            md = metadata(user(call))
            if haskey(md, LLVM.MD_dbg)
                md[LLVM.MD_dbg]
            else
                nothing
            end
        end

        if length(call_sites) > 1
            frame = StackTraces.StackFrame("multiple call sites", "unknown", 0)
            push!(bt, frame)
        elseif length(call_sites) == 1
            backtrace(user(first(call_sites)), bt)
        end
    end

    return bt
end

function check_ir(ctx, args...)
    errors = check_ir!(ctx, IRError[], args...)
    unique!(errors)
    if !isempty(errors)
        throw(InvalidIRError(ctx, errors))
    end

    return
end

function check_ir!(ctx, errors::Vector{IRError}, mod::LLVM.Module)
    for f in functions(mod)
        check_ir!(ctx, errors, f)
    end

    return errors
end

function check_ir!(ctx, errors::Vector{IRError}, f::LLVM.Function)
    for bb in blocks(f), inst in instructions(bb)
        if isa(inst, LLVM.CallInst)
            check_ir!(ctx, errors, inst)
        end
    end

    return errors
end

const special_fns = ("vprintf", "__nvvm_reflect")

const libjulia = Ref{Ptr{Cvoid}}(C_NULL)

function check_ir!(ctx, errors::Vector{IRError}, inst::LLVM.CallInst)
    dest = called_value(inst)
    if isa(dest, LLVM.Function)
        fn = LLVM.name(dest)

        # detect calls to undefined functions
        if isdeclaration(dest) && intrinsic_id(dest) == 0 && !(fn in special_fns)
            # figure out if the function lives in the Julia runtime library
            if libjulia[] == C_NULL
                paths = filter(Libdl.dllist()) do path
                    name = splitdir(path)[2]
                    startswith(name, "libjulia")
                end
                libjulia[] = Libdl.dlopen(first(paths))
            end

            bt = backtrace(inst)
            if Libdl.dlsym_e(libjulia[], fn) != C_NULL
                push!(errors, (RUNTIME_FUNCTION, bt, LLVM.name(dest)))
            else
                push!(errors, (UNKNOWN_FUNCTION, bt, LLVM.name(dest)))
            end
        end
    elseif isa(dest, InlineAsm)
        # let's assume it's valid ASM
    elseif isa(dest, ConstantExpr)
        # detect calls to literal pointers
        # FIXME: can we detect these properly?
        if occursin("inttoptr", string(dest))
            # extract the literal pointer
            ptr_arg = first(operands(dest))
            @compiler_assert isa(ptr_arg, ConstantInt) ctx
            ptr_val = convert(Int, ptr_arg)
            ptr = Ptr{Cvoid}(ptr_val)

            # look it up in the Julia JIT cache
            bt = backtrace(inst)
            frames = ccall(:jl_lookup_code_address, Any, (Ptr{Cvoid}, Cint,), ptr, 0)
            if length(frames) >= 1
                length(frames) > 1 && @warn "unexpected debug frame count, please file an issue"
                fn, file, line, linfo, fromC, inlined, ip = last(frames)
                push!(errors, (POINTER_FUNCTION, bt, fn))
            else
                fn, file, line, linfo, fromC, inlined, ip = last(frames)
                push!(errors, (POINTER_FUNCTION, bt, nothing))
            end
        end
    end

    return errors
end
