### Broadcasting

Base.getindex(df::AbstractDataFrame, idx::CartesianIndex{2}) = df[idx[1], idx[2]]
Base.view(df::AbstractDataFrame, idx::CartesianIndex{2}) = view(df, idx[1], idx[2])
Base.setindex!(df::AbstractDataFrame, val, idx::CartesianIndex{2}) =
    (df[idx[1], idx[2]] = val)

Base.broadcastable(df::AbstractDataFrame) = df

struct DataFrameStyle <: Base.Broadcast.BroadcastStyle end

Base.Broadcast.BroadcastStyle(::Type{<:AbstractDataFrame}) =
    DataFrameStyle()

Base.Broadcast.BroadcastStyle(::DataFrameStyle, ::Base.Broadcast.BroadcastStyle) = DataFrameStyle()
Base.Broadcast.BroadcastStyle(::Base.Broadcast.BroadcastStyle, ::DataFrameStyle) = DataFrameStyle()
Base.Broadcast.BroadcastStyle(::DataFrameStyle, ::DataFrameStyle) = DataFrameStyle()

function copyto_widen!(res::AbstractVector{T}, bc::Base.Broadcast.Broadcasted,
                       pos, col) where T
    for i in pos:length(axes(bc)[1])
        val = bc[CartesianIndex(i, col)]
        S = typeof(val)
        if S <: T || promote_type(S, T) <: T
            res[i] = val
        else
            newres = similar(Vector{promote_type(S, T)}, length(res))
            copyto!(newres, 1, res, 1, i-1)
            newres[i] = val
            return copyto_widen!(newres, bc, i + 1, 2)
        end
    end
    return res
end

function getcolbc(bcf::Base.Broadcast.Broadcasted{Style}, colind) where {Style}
    # we assume that bcf is already flattened and unaliased
    newargs = map(bcf.args) do x
        Base.Broadcast.extrude(x isa AbstractDataFrame ? x[!, colind] : x)
    end
    Base.Broadcast.Broadcasted{Style}(bcf.f, newargs, bcf.axes)
end

function Base.copy(bc::Base.Broadcast.Broadcasted{DataFrameStyle})
    ndim = length(axes(bc))
    if ndim != 2
        throw(DimensionMismatch("cannot broadcast a data frame into $ndim dimensions"))
    end
    bcf = Base.Broadcast.flatten(bc)
    colnames = unique([_names(df) for df in bcf.args if df isa AbstractDataFrame])
    if length(colnames) != 1
        wrongnames = setdiff(union(colnames...), intersect(colnames...))
        msg = join(wrongnames, ", ", " and ")
        throw(ArgumentError("Column names in broadcasted data frames must match. " *
                            "Non matching column names are $msg"))
    end
    nrows = length(axes(bcf)[1])
    df = DataFrame()
    for i in axes(bcf)[2]
        if nrows == 0
            col = Any[]
        else
            bcf′ = getcolbc(bcf, i)
            v1 = bcf′[CartesianIndex(1, i)]
            startcol = similar(Vector{typeof(v1)}, nrows)
            startcol[1] = v1
            col = copyto_widen!(startcol, bcf′, 2, i)
        end
        df[!, colnames[1][i]] = col
    end
    return df
end

### Broadcasting assignment

struct LazyNewColDataFrame{T}
    df::DataFrame
    col::T
end

Base.axes(x::LazyNewColDataFrame) = (Base.OneTo(nrow(x.df)),)

# ColReplaceDataFrame is reserved for future extensions if we decide to allow df[!, cols] .= v
# # ColReplaceDataFrame allows for column replacement in broadcasting
# struct ColReplaceDataFrame
#     df::DataFrame
#     cols::Vector{Int}
# end

# Base.axes(x::ColReplaceDataFrame) = axes(x.df)

Base.maybeview(df::AbstractDataFrame, idx::CartesianIndex{2}) = df[idx]
Base.maybeview(df::AbstractDataFrame, row::Integer, col::ColumnIndex) = df[row, col]
Base.maybeview(df::AbstractDataFrame, rows, cols) = view(df, rows, cols)

function Base.maybeview(df::DataFrame, ::typeof(!), cols)
    if !(cols isa ColumnIndex)
        throw(ArgumentError("broadcasting with column replacement is currently allowed only for single column index"))
    end
    if !(cols isa Symbol) && cols > ncol(df)
        throw(ArgumentError("creating new columns using an integer index by broadcasting is disallowed"))
    end
    # in the future we might allow cols to target multiple columns
    # in which case ColReplaceDataFrame(df, index(df)[cols]) will be returned
    LazyNewColDataFrame(df, cols)
end

Base.maybeview(df::SubDataFrame, ::typeof(!), idxs) =
    throw(ArgumentError("broadcasting with ! row selector is not allowed for SubDataFrame"))

function Base.copyto!(lazydf::LazyNewColDataFrame, bc::Base.Broadcast.Broadcasted{T}) where T
    if bc isa Base.Broadcast.Broadcasted{<:Base.Broadcast.AbstractArrayStyle{0}}
        bc_tmp = Base.Broadcast.Broadcasted{T}(bc.f, bc.args, ())
        v = Base.Broadcast.materialize(bc_tmp)
        col = similar(Vector{typeof(v)}, nrow(lazydf.df))
        copyto!(col, bc)
    else
        col = Base.Broadcast.materialize(bc)
    end
    lazydf.df[!, lazydf.col] = col
end

function _copyto_helper!(dfcol::AbstractVector, bc::Base.Broadcast.Broadcasted, col::Int)
    if axes(dfcol, 1) != axes(bc)[1]
        # this should never happen unless data frame is corrupted (has unequal column lengths)
        throw(DimensionMismatch("Dimension mismatch in broadcasting. " *
                                "The updated data frame is invalid and should not be used"))
    end
    @inbounds for row in eachindex(dfcol)
        dfcol[row] = bc[CartesianIndex(row, col)]
    end
end

function Base.Broadcast.broadcast_unalias(dest::AbstractDataFrame, src)
    for col in eachcol(dest)
        src = Base.Broadcast.unalias(col, src)
    end
    src
end

function Base.Broadcast.broadcast_unalias(dest, src::AbstractDataFrame)
    wascopied = false
    for (i, col) in enumerate(eachcol(src))
        if Base.mightalias(dest, col)
            if src isa SubDataFrame
                if !wascopied
                    src = SubDataFrame(copy(parent(src), copycols=false),
                                       index(src), rows(src))
                end
                parentidx = parentcols(index(src), i)
                parent(src)[!, parentidx] = Base.unaliascopy(parent(src)[!, parentidx])
            else
                if !wascopied
                    src = copy(src, copycols=false)
                end
                src[!, i] = Base.unaliascopy(col)
            end
            wascopied = true
        end
    end
    src
end

function _broadcast_unalias_helper(dest::AbstractDataFrame, scol::AbstractVector,
                                   src::AbstractDataFrame, col2::Int, wascopied::Bool)
    # col1 can be checked till col2 point as we are writing broadcasting
    # results from 1 to ncol
    # we go downwards because aliasing when col1 == col2 is most probable
    for col1 in col2:-1:1
        dcol = dest[!, col1]
        if Base.mightalias(dcol, scol)
            if src isa SubDataFrame
                if !wascopied
                    src =SubDataFrame(copy(parent(src), copycols=false),
                                      index(src), rows(src))
                end
                parentidx = parentcols(index(src), col2)
                parent(src)[!, parentidx] = Base.unaliascopy(parent(src)[!, parentidx])
            else
                if !wascopied
                    src = copy(src, copycols=false)
                end
                src[!, col2] = Base.unaliascopy(scol)
            end
            return src, true
        end
    end
    return src, wascopied
end

function Base.Broadcast.broadcast_unalias(dest::AbstractDataFrame, src::AbstractDataFrame)
    if size(dest, 2) != size(src, 2)
        throw(DimensionMismatch("Dimension mismatch in broadcasting."))
    end
    wascopied = false
    for col2 in axes(dest, 2)
        scol = src[!, col2]
        src, wascopied = _broadcast_unalias_helper(dest, scol, src, col2, wascopied)
    end
    src
end

function Base.copyto!(df::AbstractDataFrame, bc::Base.Broadcast.Broadcasted)
    bcf = Base.Broadcast.flatten(bc)
    colnames = unique([_names(x) for x in bcf.args if x isa AbstractDataFrame])
    if length(colnames) > 1 || (length(colnames) == 1 && _names(df) != colnames[1])
        wrongnames = setdiff(union(colnames...), intersect(colnames...))
        msg = join(wrongnames, ", ", " and ")
        throw(ArgumentError("Column names in broadcasted data frames must match. " *
                            "Non matching column names are $msg"))
    end

    bcf′ = Base.Broadcast.preprocess(df, bcf)
    for i in axes(df, 2)
        _copyto_helper!(df[!, i], getcolbc(bcf′, i), i)
    end
    df
end

function Base.copyto!(df::AbstractDataFrame, bc::Base.Broadcast.Broadcasted{<:Base.Broadcast.AbstractArrayStyle{0}})
    # special case of fast approach when bc is providing an untransformed scalar
    if bc.f === identity && bc.args isa Tuple{Any} && Base.Broadcast.isflat(bc)
        for col in axes(df, 2)
            fill!(df[!, col], bc.args[1][])
        end
        df
    else
        copyto!(df, convert(Base.Broadcast.Broadcasted{Nothing}, bc))
    end
end

# copyto! for ColReplaceDataFrame is reserved for future extensions if we decide to allow df[!, cols] .= v
# function Base.copyto!(df::ColReplaceDataFrame, bc::Base.Broadcast.Broadcasted)
#     bcf = Base.Broadcast.flatten(bc)
#     colnames = unique([_names(x) for x in bcf.args if x isa AbstractDataFrame])
#     if length(colnames) > 1 || (length(colnames) == 1 && view(_names(df.df), df.cols) != colnames[1])
#         wrongnames = setdiff(union(colnames...), intersect(colnames...))
#         msg = join(wrongnames, ", ", " and ")
#         throw(ArgumentError("Column names in broadcasted data frames must match. " *
#                             "Non matching column names are $msg"))
#     end

#     nrows = length(axes(bcf)[1])
#     for (i, colidx) in enumerate(df.cols)
#         bcf′ = getcolbc(bcf, i)
#         v1 = bcf′[CartesianIndex(1, i)]
#         startcol = similar(Vector{typeof(v1)}, nrows)
#         startcol[1] = v1
#         col = copyto_widen!(startcol, bcf′, 2, i)
#         df.df[!, colidx] = col
#     end
#     df.df
# end

Base.Broadcast.broadcast_unalias(dest::DataFrameRow, src) =
    Base.Broadcast.broadcast_unalias(parent(dest), src)

function Base.copyto!(dfr::DataFrameRow, bc::Base.Broadcast.Broadcasted)
    bc′ = Base.Broadcast.preprocess(dfr, bc)
    for I in eachindex(bc′)
        dfr[I] = bc′[I]
    end
    dfr
end
