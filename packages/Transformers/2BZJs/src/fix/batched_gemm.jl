#=
    borrow from https://github.com/Roger-luo/BatchedRoutines.jl
=#

import LinearAlgebra

@init @require CuArrays="3a865a2d-5b23-5a0f-bc46-62713ec82fae" begin
    import .CuArrays
    #batched CuArray gemm by BatchedRoutines.jl
    function batched_gemm!(transA::AbstractChar,
                           transB::AbstractChar,
                           alpha::Float32,
                           A::CuArrays.CuArray{Float32, 3},
                           B::CuArrays.CuArray{Float32, 3},
                           beta::Float32,
                           C::CuArrays.CuArray{Float32, 3})
        CuArrays.CUBLAS.gemm_strided_batched!(transA, transB, alpha, A, B, beta, C)
    end

    function batched_gemm!(transA::AbstractChar,
                           transB::AbstractChar,
                           alpha::Float64,
                           A::CuArrays.CuArray{Float64, 3},
                           B::CuArrays.CuArray{Float64, 3},
                           beta::Float64,
                           C::CuArrays.CuArray{Float64, 3})
        CuArrays.CUBLAS.gemm_strided_batched!(transA, transB, alpha, A, B, beta, C)
    end

end

#batched cpu gemm by BatchedRoutines.jl
for (gemm, elty) in
    ((:dgemm_,:Float64),
     (:sgemm_,:Float32),)
    @eval begin
        function batched_gemm!(transA::AbstractChar,
                               transB::AbstractChar,
                               alpha::($elty),
                               A::AbstractArray{$elty, 3},
                               B::AbstractArray{$elty, 3},
                               beta::($elty),
                               C::AbstractArray{$elty, 3})
            @assert !LinearAlgebra.BLAS.has_offset_axes(A, B, C)
            @assert size(A, 3) == size(B, 3) == size(C, 3) "batch size mismatch"
            m = size(A, transA == 'N' ? 1 : 2)
            ka = size(A, transA == 'N' ? 2 : 1)
            kb = size(B, transB == 'N' ? 1 : 2)
            n = size(B, transB == 'N' ? 2 : 1)
            if ka != kb || m != size(C,1) || n != size(C,2)
                throw(DimensionMismatch("A has size ($m,$ka), B has size ($kb,$n), C has size $(size(C))"))
            end
            LinearAlgebra.BLAS.chkstride1(A)
            LinearAlgebra.BLAS.chkstride1(B)
            LinearAlgebra.BLAS.chkstride1(C)

            ptrA = Base.unsafe_convert(Ptr{$elty}, A)
            ptrB = Base.unsafe_convert(Ptr{$elty}, B)
            ptrC = Base.unsafe_convert(Ptr{$elty}, C)

            for k in 1:size(A, 3)
                ccall((LinearAlgebra.BLAS.@blasfunc($gemm), LinearAlgebra.BLAS.libblas), Cvoid,
                    (Ref{UInt8}, Ref{UInt8}, Ref{LinearAlgebra.BLAS.BlasInt}, Ref{LinearAlgebra.BLAS.BlasInt},
                     Ref{LinearAlgebra.BLAS.BlasInt}, Ref{$elty}, Ptr{$elty}, Ref{LinearAlgebra.BLAS.BlasInt},
                     Ptr{$elty}, Ref{LinearAlgebra.BLAS.BlasInt}, Ref{$elty}, Ptr{$elty},
                     Ref{LinearAlgebra.BLAS.BlasInt}),
                     transA, transB, m, n,
                     ka, alpha, ptrA, max(1,stride(A,2)),
                     ptrB, max(1,stride(B,2)), beta, ptrC,
                     max(1,stride(C,2)))

                ptrA += size(A, 1) * size(A, 2) * sizeof($elty)
                ptrB += size(B, 1) * size(B, 2) * sizeof($elty)
                ptrC += size(C, 1) * size(C, 2) * sizeof($elty)
            end

            C
        end
    end
end


