

isbanded(A::AbstractTriangular) = isbanded(parent(A))
bandwidths(A::Union{UpperTriangular,UnitUpperTriangular}) =
    (min(0,bandwidth(parent(A),1)), bandwidth(parent(A),2))
bandwidths(A::Union{LowerTriangular,UnitLowerTriangular}) =
    (bandwidth(parent(A),1), min(0,bandwidth(parent(A),2)))

triangularlayout(::Type{Tri}, ::ML) where {Tri,ML<:BandedColumns} = Tri{ML}()
triangularlayout(::Type{Tri}, ::ML) where {Tri,ML<:BandedRows} = Tri{ML}()
triangularlayout(::Type{Tri}, ::ML) where {Tri,ML<:ConjLayout{<:BandedRows}} = Tri{ML}()


function tribandeddata(::TriangularLayout{'U'}, A)
    B = triangulardata(A)
    u = bandwidth(B,2)
    D = bandeddata(B)
    view(D, 1:u+1, :)
end

function tribandeddata(::TriangularLayout{'L'}, A)
    B = triangulardata(A)
    l,u = bandwidths(B)
    D = bandeddata(B)
    view(D, u+1:l+u+1, :)
end

tribandeddata(A) = tribandeddata(MemoryLayout(typeof(A)), A)


Base.replace_in_print_matrix(A::Union{UpperTriangular{<:Any,<:AbstractBandedMatrix},
                                      UnitUpperTriangular{<:Any,<:AbstractBandedMatrix}}, i::Integer, j::Integer, s::AbstractString) =
    -bandwidth(A,1) ≤ j-i ≤ bandwidth(A,2) ? s : Base.replace_with_centered_mark(s)

Base.replace_in_print_matrix(A::Union{LowerTriangular{<:Any,<:AbstractBandedMatrix},
                                      UnitLowerTriangular{<:Any,<:AbstractBandedMatrix}}, i::Integer, j::Integer, s::AbstractString) =
    -bandwidth(A,1) ≤ j-i ≤ bandwidth(A,2) ? s : Base.replace_with_centered_mark(s)

# Mul
@lazylmul UpperTriangular{T, <:AbstractBandedMatrix{T}} where T
@lazylmul UnitUpperTriangular{T, <:AbstractBandedMatrix{T}} where T
@lazylmul LowerTriangular{T, <:AbstractBandedMatrix{T}} where T
@lazylmul UnitLowerTriangular{T, <:AbstractBandedMatrix{T}} where T


@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{'U',UNIT,<:BandedColumnMajor},
                                                <:AbstractStridedLayout}) where UNIT
    A,x = M.A,M.B
    tbmv!('U', 'N', UNIT, size(A,1), bandwidth(A,2), tribandeddata(A), x)
end

@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{'L',UNIT,<:BandedColumnMajor},
                                                <:AbstractStridedLayout}) where UNIT
    A,x = M.A,M.B
    tbmv!('L', 'N', UNIT, size(A,1), bandwidth(A,1), tribandeddata(A), x)
end

@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{UPLO,UNIT,BandedRowMajor},
                                                <:AbstractStridedLayout}) where {UPLO,UNIT}
    A,x = M.A,M.B
    tbmv!(UPLO, 'T', UNIT, transpose(tribandeddata(A)), x)
end


@inline function materialize!(M::BlasMatLmulVec{<:TriangularLayout{UPLO,UNIT,ConjLayout{BandedRowMajor}},
                                                <:AbstractStridedLayout}) where {UPLO,UNIT}
    A,x = M.A,M.B
    tbmv!(UPLO, 'C', UNIT, tribandeddata(A)', dest)
end

# Ldiv
@lazyldiv UpperTriangular{T, <:AbstractBandedMatrix{T}} where T
@lazyldiv UnitUpperTriangular{T, <:AbstractBandedMatrix{T}} where T
@lazyldiv LowerTriangular{T, <:AbstractBandedMatrix{T}} where T
@lazyldiv UnitLowerTriangular{T, <:AbstractBandedMatrix{T}} where T

@inline function materialize!(M::BlasMatLdivVec{<:TriangularLayout{'U',UNIT,<:BandedColumnMajor},
                                   <:AbstractStridedLayout}) where UNIT
    A,x = M.A,M.B
    tbsv!('U', 'N', UNIT, size(A,1), bandwidth(A,2), tribandeddata(A), x)
end

@inline function materialize!(M::BlasMatLdivVec{<:TriangularLayout{'L',UNIT,<:BandedColumnMajor},
                                                <:AbstractStridedLayout}) where UNIT
    A,x = M.A,M.B
    tbsv!('L', 'N', UNIT, size(A,1), bandwidth(A,1), tribandeddata(A), x)
end

@inline function materialize!(M::BlasMatLdivVec{<:TriangularLayout{UPLO,UNIT,BandedRowMajor},
                                              <:AbstractStridedLayout}) where {UPLO,UNIT}
    A,x = M.A,M.B
    tbsv!(UPLO, 'T', UNIT, transpose(tribandeddata(A)), x)
end


@inline function materialize!(M::BlasMatLdivVec{<:TriangularLayout{UPLO,UNIT,ConjLayout{BandedRowMajor}},
                                              <:AbstractStridedLayout}) where {UPLO,UNIT}
    A,x = M.A,M.B
    tbsv!(UPLO, 'C', UNIT, tribandeddata(A)', x)
end


## generic fallback

#Generic solver using naive substitution
# manually hoisting x[j] significantly improves performance as of Dec 2015
# manually eliding bounds checking significantly improves performance as of Dec 2015
# directly indexing A.data rather than A significantly improves performance as of Dec 2015
# replacing repeated references to A.data with [Adata = A.data and references to Adata]
# does not significantly impact performance as of Dec 2015
# replacing repeated references to A.data[j,j] with [Ajj = A.data[j,j] and references to Ajj]
# does not significantly impact performance as of Dec 2015
function banded_naivesub!(::TriangularLayout{'U','N'}, A, b::AbstractVector, x::AbstractVector = b)
    require_one_based_indexing(A, b, x)
    n = size(A, 2)
    if !(n == length(b) == length(x))
        throw(DimensionMismatch("second dimension of left hand side A, $n, length of output x, $(length(x)), and length of right hand side b, $(length(b)), must be equal"))
    end
    D = triangulardata(A)
    u = bandwidth(D,2)
    @inbounds for j in n:-1:1
        iszero(D[j,j]) && throw(SingularException(j))
        xj = x[j] = D[j,j] \ b[j]
        for i in j-1:-1:max(1,j-u) # counterintuitively 1:j-1 performs slightly better
            b[i] -= D[i,j] * xj
        end
    end
    x
end
function banded_naivesub!(::TriangularLayout{'U','U'}, A, b::AbstractVector, x::AbstractVector = b)
    require_one_based_indexing(A, b, x)
    n = size(A, 2)
    if !(n == length(b) == length(x))
        throw(DimensionMismatch("second dimension of left hand side A, $n, length of output x, $(length(x)), and length of right hand side b, $(length(b)), must be equal"))
    end
    D = triangulardata(A)
    u = bandwidth(D,2)
    @inbounds for j in n:-1:1
        xj = x[j] = b[j]
        for i in j-1:-1:max(1,j-u) # counterintuitively 1:j-1 performs slightly better
            b[i] -= D[i,j] * xj
        end
    end
    x
end
function banded_naivesub!(::TriangularLayout{'L','N'}, A, b::AbstractVector, x::AbstractVector = b)
    require_one_based_indexing(A, b, x)
    n = size(A, 2)
    if !(n == length(b) == length(x))
        throw(DimensionMismatch("second dimension of left hand side A, $n, length of output x, $(length(x)), and length of right hand side b, $(length(b)), must be equal"))
    end
    D = triangulardata(A)
    l = bandwidth(D,1)
    @inbounds for j in 1:n
        iszero(D[j,j]) && throw(SingularException(j))
        xj = x[j] = D[j,j] \ b[j]
        for i in j+1:min(j+l,n)
            b[i] -= D[i,j] * xj
        end
    end
    x
end
function banded_naivesub!(::TriangularLayout{'L','U'}, A, b::AbstractVector, x::AbstractVector = b)
    require_one_based_indexing(A, b, x)
    n = size(A, 2)
    if !(n == length(b) == length(x))
        throw(DimensionMismatch("second dimension of left hand side A, $n, length of output x, $(length(x)), and length of right hand side b, $(length(b)), must be equal"))
    end
    D = triangulardata(A)
    l = bandwidth(D,1)
    @inbounds for j in 1:n
        xj = x[j] = b[j]
        for i in j+1:min(j+l,n)
            b[i] -= D[i,j] * xj
        end
    end
    x
end

function materialize!(M::MatLdivVec{<:TriangularLayout{UPLO,UNIT,<:AbstractBandedLayout}}) where {UPLO,UNIT}
    A,x = M.A, M.B
    banded_naivesub!(MemoryLayout(typeof(A)), A, x)
end