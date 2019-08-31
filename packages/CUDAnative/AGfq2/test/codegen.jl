@testset "code generation" begin

############################################################################################

@testset "LLVM IR" begin

@testset "basic reflection" begin
    @eval llvm_valid_kernel() = return
    @eval llvm_invalid_kernel() = 1

    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{}; optimize=false, dump_module=true))

    # module should contain our function + a generic call wrapper
    @test occursin("define void @julia_llvm_valid_kernel", ir)
    @test !occursin("define %jl_value_t* @jlcall_", ir)

    # there should be no debug metadata
    @test !occursin("!dbg", ir)

    @test CUDAnative.code_llvm(devnull, llvm_invalid_kernel, Tuple{}) == nothing
    @test_throws CUDAnative.KernelError CUDAnative.code_llvm(devnull, llvm_invalid_kernel, Tuple{}; kernel=true) == nothing
end

@testset "exceptions" begin
    @eval codegen_exception() = throw(DivideError())
    ir = sprint(io->CUDAnative.code_llvm(io, codegen_exception, Tuple{}))

    # plain exceptions should get lowered to cuprintf (see `raise_exception`)
    @test occursin("vprintf", ir)
    # not a jl_throw referencing a jl_value_t representing the exception
    @test !occursin("jl_value_t", ir)
    @test !occursin("jl_throw", ir)
end

@testset "sysimg" begin
    # bug: use a system image function

    @eval function codegen_call_sysimg(a,i)
        Base.pointerset(a, 0, mod1(i,10), 8)
    end

    ir = sprint(io->CUDAnative.code_llvm(io, codegen_call_sysimg, Tuple{Ptr{Int},Int}))
    @test !occursin("jlsys_", ir)
end

@testset "child functions" begin
    # we often test using `@noinline sink` child functions, so test whether these survive
    @eval @noinline codegen_child(i) = sink(i)
    @eval codegen_parent(i) = codegen_child(i)

    ir = sprint(io->CUDAnative.code_llvm(io, codegen_parent, Tuple{Int}))
    @test occursin(r"call .+ @julia_codegen_child_", ir)
end

@testset "JuliaLang/julia#21121" begin
    @eval function codegen_tuple_leak()
        weight_matrix = @cuStaticSharedMem(Float32, (16, 16))
        sync_threads()
        weight_matrix[1, 16] *= 2
        sync_threads()
    end

    ir = sprint(io->CUDAnative.code_llvm(io, codegen_tuple_leak, Tuple{}))
    @test !occursin("inttoptr", ir)
end

@testset "kernel functions" begin
@testset "wrapper function aggregate rewriting" begin
    @eval codegen_aggregates(x) = return

    @eval struct Aggregate
        x::Int
    end

    ir = sprint(io->CUDAnative.code_llvm(io, codegen_aggregates, Tuple{Aggregate}))
    @test occursin(r"@julia_codegen_aggregates_\d+\({ i64 }( addrspace\(\d+\))?\*", ir)

    ir = sprint(io->CUDAnative.code_llvm(io, codegen_aggregates, Tuple{Aggregate}; kernel=true))
    @test occursin(r"@ptxcall_codegen_aggregates_\d+\({ i64 }\)", ir)
end

@testset "property_annotations" begin
    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{}; dump_module=true))
    @test !occursin("nvvm.annotations", ir)

    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{};
                                         dump_module=true, kernel=true))
    @test occursin("nvvm.annotations", ir)
    @test !occursin("maxntid", ir)
    @test !occursin("reqntid", ir)
    @test !occursin("minctasm", ir)
    @test !occursin("maxnreg", ir)

    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{};
                                         dump_module=true, kernel=true, maxthreads=42))
    @test occursin("maxntidx\", i32 42", ir)
    @test occursin("maxntidy\", i32 1", ir)
    @test occursin("maxntidz\", i32 1", ir)

    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{};
                                         dump_module=true, kernel=true, minthreads=42))
    @test occursin("reqntidx\", i32 42", ir)
    @test occursin("reqntidy\", i32 1", ir)
    @test occursin("reqntidz\", i32 1", ir)

    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{};
                                         dump_module=true, kernel=true, blocks_per_sm=42))
    @test occursin("minctasm\", i32 42", ir)

    ir = sprint(io->CUDAnative.code_llvm(io, llvm_valid_kernel, Tuple{};
                                         dump_module=true, kernel=true, maxregs=42))
    @test occursin("maxnreg\", i32 42", ir)
end
end

@testset "LLVM D32593" begin
    @eval struct llvm_D32593_struct
        foo::Float32
        bar::Float32
    end

    @eval llvm_D32593(arr) = arr[1].foo

    CUDAnative.code_llvm(devnull, llvm_D32593, Tuple{CuDeviceVector{llvm_D32593_struct,AS.Global}})
end

@testset "kernel names" begin
    @eval codegen_regular() = return
    @eval codegen_closure = ()->return

    function test_name(f, name; kwargs...)
        code = sprint(io->CUDAnative.code_llvm(io, f, Tuple{}; kwargs...))
        @test occursin(name, code)
    end

    test_name(codegen_regular, "julia_codegen_regular")
    test_name(codegen_regular, "julia_codegen_renamed"; alias="codegen_renamed")

    test_name(codegen_regular, "ptxcall_codegen_regular"; kernel=true)
    test_name(codegen_regular, "ptxcall_codegen_renamed"; kernel=true, alias="codegen_renamed")

    test_name(codegen_closure, "julia_anonymous")
    test_name(codegen_closure, "julia_codegen_renamed"; alias="codegen_renamed")

    test_name(codegen_closure, "ptxcall_anonymous"; kernel=true)
    test_name(codegen_closure, "ptxcall_codegen_renamed"; kernel=true, alias="codegen_renamed")
end

@testset "PTX TBAA" begin
    @eval codegen_load(ptr) = unsafe_load(ptr)
    @eval codegen_store(ptr) = unsafe_store!(ptr, 0)

    for f in (codegen_load, codegen_store)
        ir = sprint(io->CUDAnative.code_llvm(io, f,
                                             Tuple{CUDAnative.DevicePtr{Float32,AS.Global}};
                                             dump_module=true))
        @test occursin("ptxtbaa_global", ir)

        # no TBAA on generic pointers
        ir = sprint(io->CUDAnative.code_llvm(io, f,
                                             Tuple{CUDAnative.DevicePtr{Float32,AS.Generic}};
                                             dump_module=true))
        @test !occursin("ptxtbaa", ir)
    end


    @eval codegen_cached_load(ptr) = unsafe_cached_load(ptr)

    ir = sprint(io->CUDAnative.code_llvm(io, codegen_cached_load,
                                         Tuple{CUDAnative.DevicePtr{Float32,AS.Global}};
                                         dump_module=true))
    @test occursin("ptxtbaa_global", ir)
end

@testset "tracked pointers" begin
    @eval function codegen_tracked_ptr(a)
        a[1] = 1
        return
    end

    # this used to throw an LLVM assertion (#223)
    CUDAnative.code_llvm(devnull, codegen_tracked_ptr, Tuple{Vector{Int}}; kernel=true)
end

end


############################################################################################

@testset "PTX assembly" begin

@testset "basic reflection" begin
    @eval ptx_valid_kernel() = return
    @eval ptx_invalid_kernel() = 1

    @test CUDAnative.code_ptx(devnull, ptx_valid_kernel, Tuple{}) == nothing
    @test CUDAnative.code_ptx(devnull, ptx_invalid_kernel, Tuple{}) == nothing
    @test_throws CUDAnative.KernelError CUDAnative.code_ptx(devnull, ptx_invalid_kernel, Tuple{}; kernel=true)
end

@testset "child functions" begin
    # we often test using @noinline child functions, so test whether these survive
    # (despite not having side-effects)
    @eval @noinline ptx_child(i) = sink(i)
    @eval function ptx_parent(i)
        ptx_child(i)
        return
    end

    asm = sprint(io->CUDAnative.code_ptx(io, ptx_parent, Tuple{Int64}))
    @test occursin(r"call.uni\s+julia_ptx_child_"m, asm)
end

@testset "kernel functions" begin
    @eval @noinline ptx_nonentry(i) = sink(i)
    @eval function ptx_entry(i)
        ptx_nonentry(i)
        return
    end

    asm = sprint(io->CUDAnative.code_ptx(io, ptx_entry, Tuple{Int64}; kernel=true))
    @test occursin(r"\.visible \.entry ptxcall_ptx_entry_", asm)
    @test !occursin(r"\.visible \.func julia_ptx_nonentry_", asm)
    @test occursin(r"\.func julia_ptx_nonentry_", asm)

@testset "property_annotations" begin
    asm = sprint(io->CUDAnative.code_ptx(io, ptx_entry, Tuple{Int64}; kernel=true))
    @test !occursin("maxntid", asm)

    asm = sprint(io->CUDAnative.code_ptx(io, ptx_entry, Tuple{Int64};
                                         kernel=true, maxthreads=42))
    @test occursin(".maxntid 42, 1, 1", asm)

    asm = sprint(io->CUDAnative.code_ptx(io, ptx_entry, Tuple{Int64};
                                         kernel=true, minthreads=42))
    @test occursin(".reqntid 42, 1, 1", asm)

    asm = sprint(io->CUDAnative.code_ptx(io, ptx_entry, Tuple{Int64};
                                         kernel=true, blocks_per_sm=42))
    @test occursin(".minnctapersm 42", asm)

    if LLVM.version() >= v"4.0"
        asm = sprint(io->CUDAnative.code_ptx(io, ptx_entry, Tuple{Int64};
                                             kernel=true, maxregs=42))
        @test occursin(".maxnreg 42", asm)
    end
end
end

@testset "idempotency" begin
    # bug: generate code twice for the same kernel (jl_to_ptx wasn't idempotent)

    @eval codegen_idempotency() = return
    CUDAnative.code_ptx(devnull, codegen_idempotency, Tuple{})
    CUDAnative.code_ptx(devnull, codegen_idempotency, Tuple{})
end

@testset "child function reuse" begin
    # bug: depending on a child function from multiple parents resulted in
    #      the child only being present once

    @eval @noinline codegen_child_reuse_child(i) = sink(i)
    @eval function codegen_child_reuse_parent1(i)
        codegen_child_reuse_child(i)
        return
    end

    asm = sprint(io->CUDAnative.code_ptx(io, codegen_child_reuse_parent1, Tuple{Int}))
    @test occursin(r".func julia_codegen_child_reuse_child_", asm)

    @eval function codegen_child_reuse_parent2(i)
        codegen_child_reuse_child(i+1)
        return
    end

    asm = sprint(io->CUDAnative.code_ptx(io, codegen_child_reuse_parent2, Tuple{Int}))
    @test occursin(r".func julia_codegen_child_reuse_child_", asm)
end

@testset "child function reuse bis" begin
    # bug: similar, but slightly different issue as above
    #      in the case of two child functions
    @eval @noinline codegen_child_reuse_bis_child1(i) = sink(i)
    @eval @noinline codegen_child_reuse_bis_child2(i) = sink(i+1)
    @eval function codegen_child_reuse_bis_parent1(i)
        codegen_child_reuse_bis_child1(i) + codegen_child_reuse_bis_child2(i)
        return
    end
    asm = sprint(io->CUDAnative.code_ptx(io, codegen_child_reuse_bis_parent1, Tuple{Int}))

    @eval function codegen_child_reuse_bis_parent2(i)
        codegen_child_reuse_bis_child1(i+1) + codegen_child_reuse_bis_child2(i+1)
        return
    end
    asm = sprint(io->CUDAnative.code_ptx(io, codegen_child_reuse_bis_parent2, Tuple{Int}))
end

@testset "indirect sysimg function use" begin
    # issue #9: re-using sysimg functions should force recompilation
    #           (host fldmod1->mod1 throws, so the PTX code shouldn't contain a throw)

    # NOTE: Int32 to test for #49

    @eval function codegen_recompile(out)
        wid, lane = fldmod1(unsafe_load(out), Int32(32))
        unsafe_store!(out, wid)
        return
    end

    asm = sprint(io->CUDAnative.code_ptx(io, codegen_recompile, Tuple{Ptr{Int32}}))
    @test !occursin("jl_throw", asm)
    @test !occursin("jl_invoke", asm)   # forced recompilation should still not invoke
end

@testset "compile for host after PTX" begin
    # issue #11: re-using host functions after PTX compilation
    @eval @noinline codegen_recompile_bis_child(i) = sink(i+1)

    @eval function codegen_recompile_bis_fromhost()
        codegen_recompile_bis_child(10)
    end

    @eval function codegen_recompile_bis_fromptx()
        codegen_recompile_bis_child(10)
        return
    end

    CUDAnative.code_ptx(devnull, codegen_recompile_bis_fromptx, Tuple{})
    @test codegen_recompile_bis_fromhost() == 11
end

@testset "LLVM intrinsics" begin
    # issue #13 (a): cannot select trunc
    @eval function codegen_issue_13(x)
        unsafe_trunc(Int, x)
        return
    end
    CUDAnative.code_ptx(devnull, codegen_issue_13, Tuple{Float64})
end

@testset "kernel names" begin
    @eval codegen_regular() = nothing
    @eval codegen_closure = ()->nothing

    function test_name(f, name; kwargs...)
        code = sprint(io->CUDAnative.code_ptx(io, f, Tuple{}; kwargs...))
        @test occursin(name, code)
    end

    test_name(codegen_regular, "julia_codegen_regular")
    test_name(codegen_regular, "julia_codegen_renamed"; alias="codegen_renamed")

    test_name(codegen_regular, "ptxcall_codegen_regular"; kernel=true)
    test_name(codegen_regular, "ptxcall_codegen_renamed"; kernel=true, alias="codegen_renamed")

    test_name(codegen_closure, "julia_anonymous")
    test_name(codegen_closure, "julia_codegen_renamed"; alias="codegen_renamed")

    test_name(codegen_closure, "ptxcall_anonymous"; kernel=true)
    test_name(codegen_closure, "ptxcall_codegen_renamed"; kernel=true, alias="codegen_renamed")
end

@testset "exception arguments" begin
    @eval function codegen_exception_arguments(a)
        unsafe_store!(a, trunc(Int, unsafe_load(a)))
        return
    end

    CUDAnative.code_ptx(devnull, codegen_exception_arguments, Tuple{Ptr{Float64}})
end

end


############################################################################################


@testset "errors" begin

# some validation happens in the emit_function hook, which is called by code_llvm

if VERSION >= v"0.7.0-beta.48"
@testset "recursion" begin
    @eval error_recurse_outer(i) = i > 0 ? i : error_recurse_inner(i)
    @eval @noinline error_recurse_inner(i) = i < 0 ? i : error_recurse_outer(i)

    @test_throws_message(CUDAnative.KernelError, CUDAnative.code_llvm(error_recurse_outer, Tuple{Int})) do msg
        occursin("recursion is currently not supported", msg) &&
        occursin("[1] error_recurse_outer", msg) &&
        occursin("[2] error_recurse_inner", msg) &&
        occursin("[3] error_recurse_outer", msg)
    end
end
end

if VERSION >= v"0.7.0-beta.48"
@testset "base intrinsics" begin
    @eval error_base_intrinsics(i) = sin(i)

    # NOTE: we don't use test_logs in order to test all of the warning (exception, backtrace)
    logs, _ = Test.collect_test_logs() do
        CUDAnative.code_llvm(devnull, error_base_intrinsics, Tuple{Int})
    end
    @test length(logs) == 1
    record = logs[1]
    @test record.level == Base.CoreLogging.Warn
    @test record.message == "calls to Base intrinsics might be GPU incompatible"
    @test haskey(record.kwargs, :exception)
    err,bt = record.kwargs[:exception]
    err_msg = sprint(showerror, err)
    @test occursin(r"You called sin(.+) in Base.Math .+, maybe you intended to call sin(.+) in CUDAnative .+ instead?", err_msg)
    bt_msg = sprint(Base.show_backtrace, bt)
    @test occursin("[1] sin", bt_msg)
    @test occursin("[2] error_base_intrinsics", bt_msg)
end
end

# some validation happens in compile_function, which is called by code_ptx

@testset "non-isbits arguments" begin
    @eval error_use_nonbits(i) = sink(unsafe_trunc(Int,i))

    @test_throws_message(CUDAnative.KernelError, CUDAnative.code_ptx(error_use_nonbits, Tuple{BigInt})) do msg
        occursin("passing and using non-bitstype argument", msg) &&
        occursin("BigInt", msg)
    end
end

@testset "invalid LLVM IR" begin
    @eval error_invalid_ir(i) = println(i)

    @test_throws_message(CUDAnative.InvalidIRError, CUDAnative.code_ptx(error_invalid_ir, Tuple{Int})) do msg
        occursin("invalid LLVM IR", msg) &&
        occursin(CUDAnative.RUNTIME_FUNCTION, msg) &&
        occursin("[1] println", msg) &&
        occursin("[2] error_invalid_ir", msg)
    end
end

@testset "invalid LLVM IR (ccall)" begin
    @eval error_ccall(p) = (unsafe_store!(p, ccall(:time, Cint, ())); nothing)

    @test_throws_message(CUDAnative.InvalidIRError, CUDAnative.code_ptx(error_ccall, Tuple{Ptr{Int}})) do msg
        occursin("invalid LLVM IR", msg) &&
        occursin(CUDAnative.POINTER_FUNCTION, msg) &&
        occursin("[1] error_ccall", msg)
    end
end

end


############################################################################################

end
