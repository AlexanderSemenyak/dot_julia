### This support BLAS style multiplication
#           α * A * B + β C
# it represents the same thing as Mul(α, A, B) .+ Mul(β, C)
# but avoids the broadcast machinery

# Lazy representation of α*A*B + β*C
struct MulAdd{StyleA, StyleB, StyleC, T, AA, BB, CC}
    α::T
    A::AA
    B::BB
    β::T
    C::CC
end

MulAdd{StyleA,StyleB,StyleC}(α::T, A::AA, B::BB, β::T, C::CC) where {StyleA,StyleB,StyleC,T,AA,BB,CC} =
    MulAdd{StyleA,StyleB,StyleC,T,AA,BB,CC}(α,A,B,β,C)

function MulAdd{StyleA,StyleB,StyleC}(αT, A, B, βV, C) where {StyleA,StyleB,StyleC}
    α,β = promote(αT,βV)
    MulAdd{StyleA,StyleB,StyleC}(α, A, B, β, C)
end

struct Lmul{StyleA, StyleB, TypeA, TypeB}
    A::TypeA
    B::TypeB
end

Lmul(A::TypeA, B::TypeB) where {TypeA,TypeB} = Lmul{typeof(MemoryLayout(TypeA)),typeof(MemoryLayout(TypeB)),TypeA,TypeB}(A,B)


function MulAdd(styleA::StyleA, styleB::StyleB, styleC::StyleC, α::T, A::AA, B::BB, β::V, C::CC) where {StyleA,StyleB,StyleC,T,V,AA,BB,CC}
    axes(A,2) == axes(B,1) || throw(DimensionMismatch())
    axes(A,1) == axes(C,1) || throw(DimensionMismatch())
    axes(B,2) == axes(C,2) || throw(DimensionMismatch())
    MulAdd{StyleA,StyleB,StyleC,promote_type(T,V),AA,BB,CC}(styleA, styleB, styleC, α, A, B, β, C)
end

@inline MulAdd(α, A::AA, B::BB, β, C::CC) where {AA,BB,CC} = 
    MulAdd{typeof(MemoryLayout(AA)), typeof(MemoryLayout(BB)), typeof(MemoryLayout(CC))}(α, A, B, β, C)

eltype(::MulAdd{StyleA,StyleB,StyleC,T,AA,BB,CC}) where {StyleA,StyleB,StyleC,T,AA,BB,CC} =
     promote_type(T, eltype(AA), eltype(BB), eltype(CC))

size(M::MulAdd, p::Int) = size(M)[p]
axes(M::MulAdd, p::Int) = axes(M)[p]
length(M::MulAdd) = prod(size(M))
size(M::MulAdd) = length.(axes(M))
axes(M::MulAdd) = axes(M.C)

BroadcastStyle(::Type{<:MulAdd}) = ApplyBroadcastStyle()
BroadcastStyle(::Type{<:Lmul}) = ApplyBroadcastStyle()

struct LmulStyle <: AbstractArrayApplyStyle end
abstract type AbstractMulAddStyle <: AbstractArrayApplyStyle end
struct MulAddStyle <: AbstractMulAddStyle end


@inline mulapplystyle(A, B) = MulAddStyle()
@inline mulapplystyle(α, A, B) = MulAddStyle()

ApplyStyle(::typeof(*), ::Type{A}, ::Type{B}) where {A<:AbstractMatrix,B<:AbstractVector} =
    mulapplystyle(MemoryLayout(A), MemoryLayout(B))
ApplyStyle(::typeof(*), ::Type{A}, ::Type{B}) where {A<:AbstractMatrix,B<:AbstractMatrix} =
    mulapplystyle(MemoryLayout(A), MemoryLayout(B))    
ApplyStyle(::typeof(*), ::Type{A}, ::Type{B}) where {A<:AbstractVector,B<:AbstractMatrix} =
    mulapplystyle(MemoryLayout(A), MemoryLayout(B))   
ApplyStyle(::typeof(*), ::Type{α}, ::Type{A}, ::Type{B}) where {α<:Number, A<:AbstractMatrix,B<:AbstractVector} =
    mulapplystyle(MemoryLayout(α), MemoryLayout(A), MemoryLayout(B))
ApplyStyle(::typeof(*), ::Type{α}, ::Type{A}, ::Type{B}) where {α<:Number, A<:AbstractMatrix,B<:AbstractMatrix} =
    mulapplystyle(MemoryLayout(α), MemoryLayout(A), MemoryLayout(B))    
ApplyStyle(::typeof(*), ::Type{α}, ::Type{A}, ::Type{B}) where {α<:Number, A<:AbstractVector,B<:AbstractMatrix} =
    mulapplystyle(MemoryLayout(α), MemoryLayout(A), MemoryLayout(B))        
ApplyStyle(::typeof(+), ::Type{<:Mul{MulAddStyle}}, ::Type{<:Mul}) = MulAddStyle() # TODO: simpler second arg
ApplyStyle(::typeof(+), ::Type{<:Mul{MulAddStyle}}, ::Type{<:AbstractArray}) = MulAddStyle()

scalarone(::Type{T}) where T = one(T)
scalarone(::Type{<:AbstractArray{T}}) where T = scalarone(T)
scalarzero(::Type{T}) where T = zero(T)
scalarzero(::Type{<:AbstractArray{T}}) where T = scalarzero(T)


_αAB(M::Mul{<:AbstractMulAddStyle,<:Tuple{<:AbstractArray,<:AbstractArray}}, ::Type{T}) where T = tuple(scalarone(T), M.args...)
_αAB(M::Mul{<:AbstractMulAddStyle,<:Tuple{<:Number,<:AbstractArray,<:AbstractArray}}, ::Type{T}) where T = M.args
_αABβC(M::Mul, ::Type{T}) where T = tuple(_αAB(M, T)..., scalarzero(T), nothing)

_βC(M::Mul, ::Type{T}) where T = M.args
_βC(M::AbstractArray, ::Type{T}) where T = (scalarone(T), M)

_αABβC(M::Applied{<:AbstractMulAddStyle,typeof(+)}, ::Type{T}) where T = 
    tuple(_αAB(M.args[1], T)..., _βC(M.args[2], T)...)


copy(M::Applied{<:AbstractMulAddStyle}) = copyto!(similar(M), M)

@inline function copyto!(dest::AbstractArray{T}, M::Applied{<:AbstractMulAddStyle}) where T
    α,A,B,β,C = _αABβC(M, T)
    if C == nothing
        if !isbitstype(T) # instantiate
            dest .= β .* view(A,:,1) .* Ref(B[1])  # get shape right
        end
    elseif C !== dest 
        copyto!(dest, C)
    end
    materialize!(MulAdd(α, A, B, β, dest))
end

const ArrayMulArrayAdd{StyleA,StyleB,StyleC} = MulAdd{StyleA,StyleB,StyleC,<:Any,<:AbstractArray,<:AbstractArray,<:AbstractArray}
const MatMulVecAdd{StyleA,StyleB,StyleC} = MulAdd{StyleA,StyleB,StyleC,<:Any,<:AbstractMatrix,<:AbstractVector,<:AbstractVector}
const MatMulMatAdd{StyleA,StyleB,StyleC} = MulAdd{StyleA,StyleB,StyleC,<:Any,<:AbstractMatrix,<:AbstractMatrix,<:AbstractMatrix}
const VecMulMatAdd{StyleA,StyleB,StyleC} = MulAdd{StyleA,StyleB,StyleC,<:Any,<:AbstractVector,<:AbstractMatrix,<:AbstractMatrix}

broadcastable(M::MulAdd) = M
broadcastable(M::Lmul) = M

const BlasMatMulVecAdd{StyleA,StyleB,StyleC,T<:BlasFloat} = MulAdd{StyleA,StyleB,StyleC,T,<:AbstractMatrix{T},<:AbstractVector{T},<:AbstractVector{T}}
const BlasMatMulMatAdd{StyleA,StyleB,StyleC,T<:BlasFloat} = MulAdd{StyleA,StyleB,StyleC,T,<:AbstractMatrix{T},<:AbstractMatrix{T},<:AbstractMatrix{T}}
const BlasVecMulMatAdd{StyleA,StyleB,StyleC,T<:BlasFloat} = MulAdd{StyleA,StyleB,StyleC,T,<:AbstractVector{T},<:AbstractMatrix{T},<:AbstractMatrix{T}}

const MatLmulVec{StyleA,StyleB} = Lmul{StyleA,StyleB,<:AbstractMatrix,<:AbstractVector}
const MatLmulMat{StyleA,StyleB} = Lmul{StyleA,StyleB,<:AbstractMatrix,<:AbstractMatrix}

const BlasMatLmulVec{StyleA,StyleB,T<:BlasFloat} = Lmul{StyleA,StyleB,<:AbstractMatrix{T},<:AbstractVector{T}}
const BlasMatLmulMat{StyleA,StyleB,T<:BlasFloat} = Lmul{StyleA,StyleB,<:AbstractMatrix{T},<:AbstractMatrix{T}}

@inline function copyto!(dest::AbstractArray, M::MulAdd)
    M.C ≡ dest || copyto!(dest, M.C)
    materialize!(MulAdd(M.α,M.A,M.B,M.β,dest))
end

import LinearAlgebra: tilebufsize, Abuf, Bbuf, Cbuf

# Modified from LinearAlgebra._generic_matmatmul!
function tile_size(T, S, R)
    tile_size = 0
    if isbitstype(R) && isbitstype(T) && isbitstype(S)
        tile_size = floor(Int, sqrt(tilebufsize / max(sizeof(R), sizeof(S), sizeof(T))))
    end
    tile_size
end

function tiled_blasmul!(tile_size, α, A::AbstractMatrix{T}, B::AbstractMatrix{S}, β, C::AbstractMatrix{R}) where {S,T,R}
    mA, nA = size(A)
    mB, nB = size(B)
    nA == mB || throw(DimensionMismatch("Dimensions must match"))
    size(C) == (mA, nB) || throw(DimensionMismatch("Dimensions must match"))


    @inbounds begin
        sz = (tile_size, tile_size)
        # FIXME: This code is completely invalid!!!
        Atile = unsafe_wrap(Array, convert(Ptr{T}, pointer(Abuf[Threads.threadid()])), sz)
        Btile = unsafe_wrap(Array, convert(Ptr{S}, pointer(Bbuf[Threads.threadid()])), sz)

        z1 = zero(A[1, 1]*B[1, 1] + A[1, 1]*B[1, 1])
        z = convert(promote_type(typeof(z1), R), z1)

        if mA < tile_size && nA < tile_size && nB < tile_size
            copy_transpose!(Atile, 1:nA, 1:mA, 'N', A, 1:mA, 1:nA)
            copyto!(Btile, 1:mB, 1:nB, 'N', B, 1:mB, 1:nB)
            for j = 1:nB
                boff = (j-1)*tile_size
                for i = 1:mA
                    aoff = (i-1)*tile_size
                    s = z
                    for k = 1:nA
                        s += Atile[aoff+k] * Btile[boff+k]
                    end
                    C[i,j] = α*s + β*C[i,j]
                end
            end
        else
            # FIXME: This code is completely invalid!!!
            Ctile = unsafe_wrap(Array, convert(Ptr{R}, pointer(Cbuf[Threads.threadid()])), sz)
            for jb = 1:tile_size:nB
                jlim = min(jb+tile_size-1,nB)
                jlen = jlim-jb+1
                for ib = 1:tile_size:mA
                    ilim = min(ib+tile_size-1,mA)
                    ilen = ilim-ib+1
                    copyto!(Ctile, 1:ilen, 1:jlen, C, ib:ilim, jb:jlim)
                    lmul!(β,Ctile)
                    for kb = 1:tile_size:nA
                        klim = min(kb+tile_size-1,mB)
                        klen = klim-kb+1
                        copy_transpose!(Atile, 1:klen, 1:ilen, 'N', A, ib:ilim, kb:klim)
                        copyto!(Btile, 1:klen, 1:jlen, 'N', B, kb:klim, jb:jlim)
                        for j=1:jlen
                            bcoff = (j-1)*tile_size
                            for i = 1:ilen
                                aoff = (i-1)*tile_size
                                s = z
                                for k = 1:klen
                                    s += Atile[aoff+k] * Btile[bcoff+k]
                                end
                                Ctile[bcoff+i] += α*s
                            end
                        end
                    end
                    copyto!(C, ib:ilim, jb:jlim, Ctile, 1:ilen, 1:jlen)
                end
            end
        end
    end

    C
end

function default_blasmul!(α, A::AbstractMatrix, B::AbstractMatrix, β, C::AbstractMatrix)
    mA, nA = size(A)
    mB, nB = size(B)
    nA == mB || throw(DimensionMismatch("Dimensions must match"))
    size(C) == (mA, nB) || throw(DimensionMismatch("Dimensions must match"))

    @inbounds for k = 1:mA, j = 1:nB
        z2 = zero(A[k, 1]*B[1, j] + A[k, 1]*B[1, j])
        Ctmp = convert(promote_type(eltype(C), typeof(z2)), z2)
        @simd for ν = 1:size(A,2)
            Ctmp = muladd(A[k, ν],B[ν, j],Ctmp)
        end
        C[k,j] = muladd(α,Ctmp, β*C[k,j])
    end
    C
end

function default_blasmul!(α, A::AbstractMatrix, B::AbstractVector, β, C::AbstractVector)
    mA, nA = size(A)
    mB = length(B)
    nA == mB || throw(DimensionMismatch("Dimensions must match"))
    length(C) == mA || throw(DimensionMismatch("Dimensions must match"))

    lmul!(β, C)
    (nA == 0 || mB == 0)  && return C

    z = zero(A[1]*B[1] + A[1]*B[1])
    Astride = size(A, 1) # use size, not stride, since its not pointer arithmetic

    @inbounds for k = 1:mB
        aoffs = (k-1)*Astride
        b = B[k]
        for i = 1:mA
            C[i] += α * A[aoffs + i] * b
        end
    end

    C
end

function materialize!(M::MatMulMatAdd)
    α, A, B, β, C = M.α, M.A, M.B, M.β, M.C
    if C ≡ B
        B = copy(B)
    end
    ts = tile_size(eltype(A), eltype(B), eltype(C))
    if iszero(β) # false is a "strong" zero to wipe out NaNs
        ts == 0 ? default_blasmul!(α, A, B, false, C) : tiled_blasmul!(ts, α, A, B, false, C)
    else
        ts == 0 ? default_blasmul!(α, A, B, β, C) : tiled_blasmul!(ts, α, A, B, β, C)
    end
end

function materialize!(M::MatMulVecAdd)
    α, A, B, β, C = M.α, M.A, M.B, M.β, M.C
    if C ≡ B
        B = copy(B)
    end
    default_blasmul!(α, A, B, iszero(β) ? false : β, C)
end

# make copy to make sure always works
@inline function _gemv!(tA, α, A, x, β, y)
    if x ≡ y
        BLAS.gemv!(tA, α, A, copy(x), β, y)
    else
        BLAS.gemv!(tA, α, A, x, β, y)
    end
end

# make copy to make sure always works
@inline function _gemm!(tA, tB, α, A, B, β, C)
    if B ≡ C
        BLAS.gemm!(tA, tB, α, A, copy(B), β, C)
    else
        BLAS.gemm!(tA, tB, α, A, B, β, C)
    end
end


@inline materialize!(M::BlasMatMulVecAdd{<:AbstractColumnMajor,<:AbstractStridedLayout,<:AbstractStridedLayout}) =
    _gemv!('N', M.α, M.A, M.B, M.β, M.C)
@inline materialize!(M::BlasMatMulVecAdd{<:AbstractRowMajor,<:AbstractStridedLayout,<:AbstractStridedLayout}) =
    _gemv!('T', M.α, transpose(M.A), M.B, M.β, M.C)
@inline materialize!(M::BlasMatMulVecAdd{<:ConjLayout{<:AbstractRowMajor},<:AbstractStridedLayout,<:AbstractStridedLayout,<:BlasComplex}) =
    _gemv!('C', M.α, M.A', M.B, M.β, M.C)

@inline materialize!(M::BlasVecMulMatAdd{<:AbstractColumnMajor,<:AbstractColumnMajor,<:AbstractColumnMajor}) =
    _gemm!('N', 'N', M.α, M.A, M.B, M.β, M.C)
@inline materialize!(M::BlasVecMulMatAdd{<:AbstractColumnMajor,<:AbstractRowMajor,<:AbstractColumnMajor}) =
    _gemm!('N', 'T', M.α, M.A, transpose(M.B), M.β, M.C)
@inline materialize!(M::BlasVecMulMatAdd{<:AbstractColumnMajor,<:ConjLayout{<:AbstractRowMajor},<:AbstractColumnMajor,<:BlasComplex}) =
    _gemm!('N', 'C', M.α, M.A, M.B', M.β, M.C)

@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:AbstractColumnMajor,<:AbstractColumnMajor}) =
    _gemm!('N', 'N', M.α, M.A, M.B, M.β, M.C)
@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:AbstractRowMajor,<:AbstractColumnMajor}) =
    _gemm!('N', 'T', M.α, M.A, transpose(M.B), M.β, M.C)
@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:ConjLayout{<:AbstractRowMajor},<:AbstractColumnMajor,<:BlasComplex}) =
    _gemm!('N', 'C', M.α, M.A, M.B', M.β, M.C)

@inline materialize!(M::BlasMatMulMatAdd{<:AbstractRowMajor,<:AbstractColumnMajor,<:AbstractColumnMajor}) =
    _gemm!('T', 'N', M.α, transpose(M.A), M.B, M.β, M.C)
@inline materialize!(M::BlasMatMulMatAdd{<:ConjLayout{<:AbstractRowMajor},<:AbstractColumnMajor,<:AbstractColumnMajor,<:BlasComplex}) =
    _gemm!('C', 'N', M.α, M.A', M.B, M.β, M.C)

@inline materialize!(M::BlasMatMulMatAdd{<:AbstractRowMajor,<:AbstractRowMajor,<:AbstractColumnMajor}) =
    _gemm!('T', 'T', M.α, transpose(M.A), transpose(M.B), M.β, M.C)
@inline materialize!(M::BlasMatMulMatAdd{<:AbstractRowMajor,<:ConjLayout{<:AbstractRowMajor},<:AbstractColumnMajor,<:BlasComplex}) =
    _gemm!('T', 'C', M.α, transpose(M.A), M.B', M.β, M.C)

@inline materialize!(M::BlasMatMulMatAdd{<:ConjLayout{<:AbstractRowMajor},<:AbstractRowMajor,<:AbstractColumnMajor,<:BlasComplex}) =
    _gemm!('C', 'T', M.α, M.A', M.B', M.β, M.C)
@inline materialize!(M::BlasMatMulMatAdd{<:ConjLayout{<:AbstractRowMajor},<:ConjLayout{<:AbstractRowMajor},<:AbstractColumnMajor,<:BlasComplex}) =
    _gemm!('C', 'C', M.α, M.A', M.B', M.β, M.C)

@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:AbstractColumnMajor,<:AbstractRowMajor}) =
    _gemm!('T', 'T', M.α, M.B, M.A, M.β, transpose(M.C))
@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:AbstractColumnMajor,<:ConjLayout{<:AbstractRowMajor},<:BlasComplex}) =
    _gemm!('C', 'C', M.α, M.B, M.A, M.β, M.C')

@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:AbstractRowMajor,<:AbstractRowMajor}) =
    _gemm!('N', 'T', M.α, transpose(M.B), M.A, M.β, transpose(M.C))
@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:AbstractRowMajor,<:ConjLayout{<:AbstractRowMajor},<:BlasComplex}) =
    _gemm!('N', 'T', M.α, transpose(M.B), M.A, M.β, M.C')
@inline materialize!(M::BlasMatMulMatAdd{<:AbstractColumnMajor,<:ConjLayout{<:AbstractRowMajor},<:ConjLayout{<:AbstractRowMajor},<:BlasComplex}) =
    _gemm!('N', 'C', M.α, M.B', M.A, M.β, M.C')

@inline materialize!(M::BlasMatMulMatAdd{<:AbstractRowMajor,<:AbstractColumnMajor,<:AbstractRowMajor}) =
    _gemm!('T', 'N', M.α, M.B, transpose(M.A), M.β, transpose(M.C))
@inline materialize!(M::BlasMatMulMatAdd{<:ConjLayout{<:AbstractRowMajor},<:AbstractColumnMajor,<:ConjLayout{<:AbstractRowMajor},<:BlasComplex}) =
    _gemm!('C', 'N', M.α, M.B, M.A', M.β, M.C')


@inline materialize!(M::BlasMatMulMatAdd{<:AbstractRowMajor,<:AbstractRowMajor,<:AbstractRowMajor}) =
    _gemm!('N', 'N', M.α, transpose(M.B), transpose(M.A), M.β, transpose(M.C))
@inline materialize!(M::BlasMatMulMatAdd{<:ConjLayout{<:AbstractRowMajor},<:ConjLayout{<:AbstractRowMajor},<:ConjLayout{<:AbstractRowMajor},<:BlasComplex}) =
    _gemm!('N', 'N', M.α, M.B', M.A', M.β, M.C')


###
# Symmetric
###

# make copy to make sure always works
@inline function _symv!(tA, α, A, x, β, y)
    if x ≡ y
        BLAS.symv!(tA, α, A, copy(x), β, y)
    else
        BLAS.symv!(tA, α, A, x, β, y)
    end
end

@inline function _hemv!(tA, α, A, x, β, y)
    if x ≡ y
        BLAS.hemv!(tA, α, A, copy(x), β, y)
    else
        BLAS.hemv!(tA, α, A, x, β, y)
    end
end


materialize!(M::BlasMatMulVecAdd{<:SymmetricLayout{<:AbstractColumnMajor},<:AbstractStridedLayout,<:AbstractStridedLayout}) =
    _symv!(symmetricuplo(M.A), M.α, symmetricdata(M.A), M.B, M.β, M.C)


materialize!(M::BlasMatMulVecAdd{<:SymmetricLayout{<:AbstractRowMajor},<:AbstractStridedLayout,<:AbstractStridedLayout}) =
    _symv!(symmetricuplo(M.A) == 'L' ? 'U' : 'L', M.α, transpose(symmetricdata(M.A)), M.B, M.β, M.C)


materialize!(M::BlasMatMulVecAdd{<:HermitianLayout{<:AbstractColumnMajor},<:AbstractStridedLayout,<:AbstractStridedLayout,<:BlasComplex}) =
    _hemv!(symmetricuplo(M.A), M.α, hermitiandata(M.A), M.B, M.β, M.C)

materialize!(M::BlasMatMulVecAdd{<:HermitianLayout{<:AbstractRowMajor},<:AbstractStridedLayout,<:AbstractStridedLayout,<:BlasComplex}) =
    _hemv!(symmetricuplo(M.A) == 'L' ? 'U' : 'L', M.α, hermitiandata(M.A)', M.B, M.β, M.C)


####
# LMul materialize
####

copy(M::Mul{LmulStyle}) = copyto!(similar(M), Lmul(M.args...))

@inline copyto!(dest::AbstractVecOrMat, M::Mul{LmulStyle}) = copyto!(dest, Lmul(M.args...))

@inline function materialize!(M::Mul{LmulStyle})
    A,x = M.args
    materialize!(Lmul(A, x))
end

copy(M::Lmul) = materialize!(Lmul(M.A,copy(M.B)))
@inline function copyto!(dest::AbstractArray, M::Lmul)
    M.B ≡ dest || copyto!(dest, M.B)
    materialize!(Lmul(M.A,dest))
end

materialize!(M::Lmul) = lmul!(M.A,M.B)


###
# Triangular
###
mulapplystyle(::TriangularLayout, ::AbstractStridedLayout) = LmulStyle()




@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{UPLO,UNIT,<:AbstractColumnMajor},
                                         <:AbstractStridedLayout, T}) where {UPLO,UNIT,T <: BlasFloat}
    A,x = M.A,M.B
    BLAS.trmv!(UPLO, 'N', UNIT, triangulardata(A), x)
end

@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{UPLO,UNIT,<:AbstractRowMajor},
                                   <:AbstractStridedLayout, T}) where {UPLO,UNIT,T <: BlasFloat}
    A,x = M.A,M.B
    BLAS.trmv!(UPLO, 'T', UNIT, transpose(triangulardata(A)), x)
end


@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{UPLO,UNIT,<:ConjLayout{<:AbstractRowMajor}},
                                   <:AbstractStridedLayout, T}) where {UPLO,UNIT,T <: BlasFloat}
    A,x = M.A,M.B
    BLAS.trmv!(UPLO, 'C', UNIT, triangulardata(A)', x)
end

# Triangular *\ Matrix

function materialize!(M::MatLmulMat{<:TriangularLayout})
    A,X = M.A,M.B
    size(A,2) == size(X,1) || thow(DimensionMismatch("Dimensions must match"))
    for j in axes(X,2)
        apply!(*, A, view(X,:,j))
    end
    X
end
