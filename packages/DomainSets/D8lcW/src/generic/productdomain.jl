# productdomain.jl
# Routines for a cartesian product of domains

###################
# Helper functions
###################

"""
Create an eltype that is suitable for a product domain. The result is a tuple
type, where each of the elements is the eltype of the corresponding element
of the product domain.
"""
_product_eltype(t) = t
_product_eltype(::Type{Tuple{T,V}}) where {T<:Real,V<:Real} =
	NTuple{2,promote_type(T,V)}
_product_eltype(::Type{Tuple{T,V}}) where {T<:Complex,V<:Complex} =
	NTuple{2,promote_type(T,V)}
product_eltype(domains...) = _product_eltype(Tuple{map(eltype, domains)...})

"""
Try to simplify the type of a product domain to a type to which it is isomorphic.
The goal is to automatically embed the product domain in ℝ^N if possible.

Examples of simplifications:
`Tuple{Float64,Float64} -> SVector{2,Float64}`
`Tuple{Tuple{Float64,Float64},Float64} -> SVector{3,Float64}`
"""
simplify_product_eltype(::Type{T}) where {T} = T
simplify_product_eltype(::Type{NTuple{N,T}}) where {N,T} = SVector{N,T}

@generated function simplify_product_eltype(::Type{Tuple{SVector{N,T},T}}) where {N,T} 
    M = N+1
    quote SVector{$M,T} end
end
@generated function simplify_product_eltype(::Type{Tuple{T,SVector{N,T}}}) where {N,T} 
    M = N+1
    quote SVector{$M,T} end
end
@generated function simplify_product_eltype(::Type{Tuple{SVector{N,T},SVector{K,T}}}) where {N,K,T} 
    M = N+K
    quote SVector{$M,T} end
end

@generated function simplify_product_eltype(::Type{Tuple{NTuple{N,T},T}}) where {N,T} 
    M = N+1
    quote SVector{$M,T} end
end
@generated function simplify_product_eltype(::Type{Tuple{T,NTuple{N,T}}}) where {N,T} 
    M = N+1
    quote SVector{$M,T} end
end
@generated function simplify_product_eltype(::Type{Tuple{NTuple{N,T},NTuple{K,T}}}) where {N,K,T} 
    M = N+K
    quote SVector{$M,T} end
end


#######################
# Main type definition
#######################

"""
A `ProductDomain` represents the cartesian product of other domains.

A product domain has two eltypes, an internal type `S` and an external type `T`.
The internal type `S` is a tuple containing the eltypes of the elements of the
product domain. The external eltype `T` is a type whose associated space is
isomorphic to that of `S`, but which has been simplified. (See also
`simplify_product_eltype`).

For example, if `S` is `Tuple{Float64,Float64}`, then `T` is `SVector{2,Float64}`.
"""
struct ProductDomain{DD,S,T} <: Domain{T}
	# D is the type of an indexable list of domains, such as a tuple
	domains	::	DD

	# Inner constructor to verify that S and T are correct
	function ProductDomain{DD,S,T}(domains) where {DD,S,T}
		@assert S == product_eltype(domains...)
		@assert isomorphic(spacetype(S),spacetype(T))
		new{DD,S,T}(domains)
	end
end

function ProductDomain(domains...)
    DD = typeof(domains)
    S = product_eltype(domains...)
	T = simplify_product_eltype(S)
    ProductDomain{DD,S,T}(domains)
end

convert(::Type{Domain{SVector{N,T}}}, d::ProductDomain{<:Tuple{Vararg{<:Any,N}}}) where {N,T} =
	ProductDomain(convert.(Domain{T}, d.domains)...)

elements(d::ProductDomain) = d.domains

internal_eltype(::Type{ProductDomain{DD,S,T}}) where {DD,S,T} = S
internal_eltype(::Type{P}) where {P <: ProductDomain} = S
internal_eltype(d::ProductDomain) = internal_eltype(typeof(d))


cross(x::Domain...) = cartesianproduct(x...)

# One can use the cartesianproduct routine to create product domains
cartesianproduct(domains::Domain...) = ProductDomain(domains...)

# We try to avoid creating nested cartesian products
cartesianproduct(d1::Domain, d2::ProductDomain) = cartesianproduct(d1, elements(d2)...)
cartesianproduct(d1::ProductDomain, d2::Domain) = cartesianproduct(elements(d1)..., d2)
cartesianproduct(d1::ProductDomain, d2::ProductDomain) = cartesianproduct(elements(d1)..., elements(d2)...)


^(d::Domain, n::Int) = cartesianproduct(d, n)

^(d::Domain{T}, ::Type{Val{N}}) where {N,T} = ProductDomain{NTuple{N,typeof(d)},NTuple{N,T},SVector{N,T}}(ntuple(i->d, Val{N}))

indomain(x, d::ProductDomain) = _indomain(convert_space(spacetype(internal_eltype(d)), x), d, elements(d))

# The line below allocates a little bit of memory...
_indomain(x, d::ProductDomain, el) = reduce(&, map(in, x, el))

# ...hence these special cases:
_indomain(x::Tuple{A,B}, d::ProductDomain, el) where {A,B} = in(x[1], el[1]) &&
    in(x[2], el[2])
_indomain(x::Tuple{A,B,C}, d::ProductDomain, el) where {A,B,C} = in(x[1], el[1]) &&
    in(x[2], el[2]) && in(x[3], el[3])
_indomain(x::Tuple{A,B,C,D}, d::ProductDomain, el) where {A,B,C,D} = in(x[1], el[1]) &&
    in(x[2], el[2]) && in(x[3], el[3]) && in(x[4], el[4])

approx_indomain(x, d::ProductDomain, tolerance) =
    _approx_indomain(convert_space(spacetype(internal_eltype(d)), x), d, elements(d), tolerance)

_approx_indomain(x, d::ProductDomain, el, tolerance) = reduce(&, map((u,v) -> approx_indomain(u,v,tolerance), x, el))

point_in_domain(d::ProductDomain) = convert_space(spaceof(d), map(point_in_domain, elements(d)))

infimum(d::ProductDomain) = convert_space(spaceof(d), map(infimum, elements(d)))
supremum(d::ProductDomain) = convert_space(spaceof(d), map(supremum, elements(d)))

isempty(d::ProductDomain) = any(isempty, d.domains)

function show(io::IO, t::ProductDomain)
    L = numelements(t)
    for i in 1:L-1
        show(io, element(t, i))
        print(io, " x ")
    end
    show(io, element(t, L))
end
