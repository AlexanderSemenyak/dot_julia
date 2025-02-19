struct SLArray{S,T,N,L,Syms} <: StaticArray{S,T,N}
  __x::SArray{S,T,N,L}
  #SLArray{Syms}(__x::StaticArray{S,T,N}) where {S,N,Syms,T} = new{S,N,Syms,T}(__x)
  SLArray{S,T,N,Syms}(__x::SArray) where {S,T,N,Syms} = new{S,T,N,length(__x),Syms}(convert.(T,__x))
  SLArray{S,Syms}(__x::SArray{S,T,N,L}) where {S,T,N,L,Syms} = new{S,T,N,L,Syms}(__x)
  SLArray{S,T,Syms}(__x::SArray{S,T,N,L}) where {S,T,N,L,Syms} = new{S,T,N,L,Syms}(__x)
  function SLArray{S,Syms}(x::Tuple) where {S,Syms}
    __x = SArray{S}(x)
    SLArray{S,Syms}(__x)
  end
  function SLArray{S,T,Syms}(x::Tuple) where {S,T,Syms}
    __x = SArray{S,T}(x)
    SLArray{S,T,Syms}(__x)
  end
  function SLArray{S,T,N,L,Syms}(x::Tuple) where {S,T,N,L,Syms}
    __x = SArray{S,T,N,L}(x)
    new{S,T,N,L,Syms}(__x)
  end
end

#####################################
# NamedTuple compatibility
#####################################
## SLArray to named tuple
function Base.convert(::Type{NamedTuple}, x::SLArray{S,T,N,L,Syms}) where {S,T,N,L,Syms}
  tup = NTuple{length(Syms),T}(x)
  NamedTuple{Syms,typeof(tup)}(tup)
end
Base.keys(x::SLArray{S,T,N,L,Syms}) where {S,T,N,L,Syms} = Syms

## Named tuple to SLArray
#=
  1. `SLArray{Tuple{2,2}}((a=1, b=2, c=3, d=4))` (need to specify size)
  2. `SLArray{Tuple{2,2}}(a=1, b=2, c=3, d=4)` : alternative form using kwargs
  3. `SLVector((a=1, b=2))` : infer size for vectors
  4. `SLVector(a=1, b=2)` : alternative form using kwargs
=#
function SLArray{Size}(tup::NamedTuple{Syms,Tup}) where {Size,Syms,Tup}
  __x = Tup(tup) # drop symbols
  SLArray{Size,Syms}(__x)
end
SLArray{Size}(;kwargs...) where {Size} = SLArray{Size}(kwargs.data)
SLVector(tup::NamedTuple) = SLArray{Tuple{length(tup)}}(tup)
SLVector(;kwargs...) = SLVector(kwargs.data)

## pairs iterator
Base.pairs(x::SLArray{S,T,N,L,Syms}) where {S,T,N,L,Syms} =
    # (label => getproperty(x, label) for label in Syms) # not type stable?
    (Syms[i] => x[i] for i in 1:length(Syms))

#####################################
# StaticArray Interface
#####################################
@inline Base.getindex(x::SLArray, i::Int) = getfield(x,:__x)[i]
@inline Base.Tuple(x::SLArray) = Tuple(x.__x)

function StaticArrays.similar_type(::Type{SLArray{S,T,N,L,Syms}}, ::Type{NewElType},
    ::Size{NewSize}) where {S,T,N,L,Syms,NewElType,NewSize}
  n = prod(NewSize)
  if n == L
    SLArray{Tuple{NewSize...},NewElType,length(NewSize),L,Syms}
  else
    SArray{Tuple{NewSize...},NewElType,length(NewSize),n}
  end
end

function Base.similar(::Type{SLArray{S,T,N,L,Syms}}, ::Type{NewElType}, ::Size{NewSize}) where {S,T,N,L,Syms,NewElType,NewSize}
  n = prod(NewSize)
  if n == L
    tmp = Array{NewElType}(undef, NewSize)
    LArray{NewElType,length(NewSize),typeof(tmp),Syms}(tmp)
  else
    MArray{Tuple{NewSize...},NewElType,length(NewSize),n}(undef)
  end
end

Base.propertynames(::SLArray{S,T,N,L,Syms}) where {S,T,N,L,Syms} = Syms
symnames(::Type{SLArray{S,T,N,L,Syms}}) where {S,T,N,L,Syms} = Syms
@inline function Base.getproperty(x::SLArray,s::Symbol)
  s == :__x ? getfield(x,:__x) : x[s]
end
@inline function Base.getindex(x::SLArray,s::Symbol)
  syms = symnames(typeof(x))
  if syms isa NamedTuple
    idxs = syms[s]
    return idxs isa Tuple ? @views(x.__x[idxs...]) : @views(x.__x[idxs])
  else
    return getindex(x,Val(s))
  end
end
@inline @generated function Base.getindex(x::SLArray,::Val{s}) where s
    idx = findfirst(y->y==s,symnames(x))
    :(getfield(x,:__x)[$idx])
end

function Base.getindex(x::SLArray,inds::AbstractArray{I,1}) where I<:Integer
    getindex(x.__x,inds)
end
function Base.getindex(x::SLArray, inds::StaticVector{<:Any, Int})
    getindex(x.__x,inds)
end

# Note: This could in the future return an SLArray with the right names
function Base.getindex(x::SLArray,s::AbstractArray{Symbol,1})
    [getindex(x,si) for si in s]
end


"""
    @SLArray Size Names
    @SLArray Eltype Size Names

Creates an anonymous function that builds a labelled static vector with eltype
`ElType` with names determined from the `Names` with size `Size`. If no eltype
is given, then the eltype is determined from the arguments in the constructor.

For example:

```julia
ABC = @SLArray (2,2) (:a,:b,:c,:d)
x = ABC(1.0,2.5,3.0,5.0)
x.a == 1.0
x.b == 2.5
x.c == x[3]
x.d == x[2,2]
EFG = @SLArray (2,2) (e=1:3, f=4, g=2:4)
y = EFG(1.0,2.5,3.0,5.0)
EFG = @SLArray (2,2) (e=(2, :), f=4, g=2:4)
```

"""
macro SLArray(dims,syms)
  dims isa Expr && (dims = dims.args)
  syms = esc(syms)
  quote
    SLArray{Tuple{$dims...},$syms}
  end
end

macro SLArray(T,dims,syms)
  dims isa Expr && (dims = dims.args)
  syms = esc(syms)
  quote
    SLArray{Tuple{$dims...},$T,$(length(dims)),$(prod(dims)),$syms}
  end
end

"""
    @SLVector Names
    @SLVector Eltype Names

Creates an anonymous function that builds a labelled static vector with eltype
`ElementType` with names determined from the `Names`. If no eltype is given,
then the eltype is determined from the values in the constructor.

For example:

```julia
ABC = @SLVector (:a,:b,:c)
x = ABC(1.0,2.5,3.0)
x.a == 1.0
x.b == 2.5
x.c == x[3]
```

"""
macro SLVector(syms)
  syms = esc(syms)
  quote
    n = $syms isa NamedTuple ? maximum(map(maximum, $syms)) : length($syms)
    SLArray{Tuple{n},$syms}
  end
end

macro SLVector(T,syms)
  T = esc(T)
  syms = esc(syms)
  quote
    n = $syms isa NamedTuple ? maximum(map(maximum, $syms)) : length($syms)
    SLArray{Tuple{n},$T,1,n,$syms}
  end
end

"""
    symbols(::SLArray{T,N,D,Syms})

Returns the labels of the `SLArray` .

For example:

    z = SLVector(a=1, b=2, c=3)
    symbols(z)  # Tuple{Symbol,Symbol,Symbol} == (:a, :b, :c)
"""
symbols(::SLArray{S,T,N,L,Syms}) where {S,T,N,L,Syms} = Syms isa NamedTuple ? keys(Syms) : Syms
