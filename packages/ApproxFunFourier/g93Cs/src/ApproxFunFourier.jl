module ApproxFunFourier
using Base, LinearAlgebra, Reexport, AbstractFFTs, FFTW, InfiniteArrays, FillArrays, FastTransforms, IntervalSets, 
            DomainSets, SpecialFunctions
            
@reexport using ApproxFunBase

import AbstractFFTs: Plan, fft, ifft
import FFTW: plan_r2r!, fftwNumber, REDFT10, REDFT01, REDFT00, RODFT00, R2HC, HC2R,
                r2r!, r2r,  plan_fft, plan_ifft, plan_ifft!, plan_fft!

import ApproxFunBase: normalize!, flipsign, FiniteRange, Fun, MatrixFun, UnsetSpace, VFun, RowVector,
                UnivariateSpace, AmbiguousSpace, SumSpace, SubSpace, WeightSpace, NoSpace, Space,
                HeavisideSpace, PointSpace,
                IntervalOrSegment, RaggedMatrix, AlmostBandedMatrix,
                AnyDomain, ZeroSpace, ArraySpace, TrivialInterlacer, BlockInterlacer, 
                AbstractTransformPlan, TransformPlan, ITransformPlan,
                ConcreteConversion, ConcreteMultiplication, ConcreteDerivative, ConcreteIntegral, CalculusOperator,
                ConcreteVolterra, Volterra, VolterraWrapper,
                MultiplicationWrapper, ConversionWrapper, DerivativeWrapper, Evaluation, EvaluationWrapper,
                Conversion, defaultConversion, defaultcoefficients, default_Fun, Multiplication, Derivative, Integral, bandwidths, 
                ConcreteEvaluation, ConcreteDefiniteLineIntegral, ConcreteDefiniteIntegral, ConcreteIntegral,
                DefiniteLineIntegral, DefiniteIntegral, ConcreteDefiniteIntegral, ConcreteDefiniteLineIntegral, IntegralWrapper,
                ReverseOrientation, ReverseOrientationWrapper, ReverseWrapper, Reverse, NegateEven, 
                Dirichlet, ConcreteDirichlet, DirichletWrapper,
                TridiagonalOperator, SubOperator, Space, @containsconstants, spacescompatible,
                hasfasttransform, canonicalspace, domain, setdomain, prectype, domainscompatible, 
                plan_transform, plan_itransform, plan_transform!, plan_itransform!, transform, itransform, hasfasttransform, 
                CanonicalTransformPlan, ICanonicalTransformPlan,
                Integral, 
                domainspace, rangespace, boundary, 
                union_rule, conversion_rule, maxspace_rule, conversion_type, maxspace, hasconversion, points, 
                rdirichlet, ldirichlet, lneumann, rneumann, ivp, bvp, 
                linesum, differentiate, integrate, linebilinearform, bilinearform, 
                UnsetNumber, coefficienttimes, subspace_coefficients, sumspacecoefficients, specialfunctionnormalizationpoint,
                Segment, IntervalOrSegmentDomain, PiecewiseSegment, isambiguous, Vec, eps, isperiodic,
                arclength, complexlength,
                invfromcanonicalD, fromcanonical, tocanonical, fromcanonicalD, tocanonicalD, canonicaldomain, setcanonicaldomain, mappoint,
                reverseorientation, checkpoints, evaluate, mul_coefficients, coefficients, coefficientmatrix, isconvertible,
                clenshaw, ClenshawPlan, sineshaw,
                toeplitz_getindex, toeplitz_axpy!, sym_toeplitz_axpy!, hankel_axpy!, ToeplitzOperator, SymToeplitzOperator, hankel_getindex, 
                SpaceOperator, ZeroOperator, InterlaceOperator,
                interlace!, reverseeven!, negateeven!, cfstype, pad!, alternatesign!, mobius,
                extremal_args, hesseneigvals, chebyshev_clenshaw, recA, recB, recC, roots,splitatroots,
                chebmult_getindex, intpow, alternatingsum,
                domaintype, diagindshift, rangetype, weight, isapproxinteger, default_Dirichlet, scal!, dotu,
                components, promoterangespace, promotedomainspace, choosedomainspace,
                block, blockstart, blockstop, blocklengths, isblockbanded, pointscompatible,
                AbstractProductSpace, MultivariateFun, BivariateSpace, 
                @wrapperstructure, @wrapperspaces, @wrapper, @calculus_operator, resizedata!, slnorm, affine_setdiff,
                complexroots

                    
import DomainSets: Domain, indomain, UnionDomain, ProductDomain, FullSpace, Point, elements, DifferenceDomain,
            Interval, ChebyshevInterval, boundary, ∂, rightendpoint, leftendpoint,
            dimension

import Base: values, convert, getindex, setindex!, *, +, -, ==, <, <=, >, |, !, !=, eltype, iterate,
                >=, /, ^, \, ∪, transpose, size, tail, broadcast, broadcast!, copyto!, copy, to_index, (:),
                similar, map, vcat, hcat, hvcat, show, summary, stride, sum, cumsum, sign, imag, conj, inv,
                complex, reverse, exp, sqrt, abs, abs2, sign, issubset, values, in, first, last, rand, intersect, setdiff,
                isless, union, angle, join, isnan, isapprox, isempty, sort, merge, promote_rule,
                minimum, maximum, extrema, argmax, argmin, findmax, findmin, isfinite,
                zeros, zero, one, promote_rule, repeat, length, resize!, isinf,
                getproperty, findfirst, unsafe_getindex, fld, cld, div, real, imag,
                @_inline_meta, eachindex, firstindex, lastindex, keys, isreal, OneTo,
                Array, Vector, Matrix, view, ones, @propagate_inbounds, print_array,
                split

import LinearAlgebra: BlasInt, BlasFloat, norm, ldiv!, mul!, det, eigvals, dot, cross,
                qr, qr!, rank, isdiag, istril, istriu, issymmetric, ishermitian,
                Tridiagonal, diagm, diagm_container, factorize, nullspace,
                Hermitian, Symmetric, adjoint, transpose, char_uplo                

import InfiniteArrays: Infinity, InfRanges, AbstractInfUnitRange, OneToInf                    

import FastTransforms: ChebyshevTransformPlan, IChebyshevTransformPlan, plan_chebyshevtransform,
                        plan_chebyshevtransform!, plan_ichebyshevtransform, plan_ichebyshevtransform!
    

# we need to import all special functions to use Calculus.symbolic_derivatives_1arg
# we can't do importall Base as we replace some Base definitions
import SpecialFunctions: sinpi, cospi, airy, besselh,
                    asinh, acosh,atanh, erfcx, dawson, erf, erfi,
                    sin, cos, sinh, cosh, airyai, airybi, airyaiprime, airybiprime,
                    hankelh1, hankelh2, besselj, besselj0, bessely, besseli, besselk,
                    besselkx, hankelh1x, hankelh2x, exp2, exp10, log2, log10,
                    tan, tanh, csc, asin, acsc, sec, acos, asec,
                    cot, atan, acot, sinh, csch, asinh, acsch,
                    sech, acosh, asech, tanh, coth, atanh, acoth,
                    expm1, log1p, lfact, sinc, cosc, erfinv, erfcinv, beta, lbeta,
                    eta, zeta, gamma,  lgamma, polygamma, invdigamma, digamma, trigamma,
                    abs, sign, log, expm1, tan, abs2, sqrt, angle, max, min, cbrt, log,
                    atan, acos, asin, erfc, inv                        

export Fourier, Taylor, Hardy, CosSpace, SinSpace, Laurent, PeriodicDomain

include("utils.jl")
include("Domains/Domains.jl")

for T in (:CosSpace,:SinSpace)
    @eval begin
        struct $T{D<:PeriodicDomain,R} <: Space{D,R}
            domain::D
            $T{D,R}(d::PeriodicDomain) where {D,R} = new(convert(D,d))
            $T{D,R}(d::D) where{D,R} = new(d)
        end
        $T(d::PeriodicDomain) = $T{typeof(d),real(prectype(d))}(d)
        $T(d) = $T(convert(PeriodicDomain, d))
        $T() = $T(PeriodicSegment())
        spacescompatible(a::$T,b::$T) = domainscompatible(a,b)
        hasfasttransform(::$T) = true
        canonicalspace(S::$T) = Fourier(domain(S))
        setdomain(S::$T,d::PeriodicDomain) = $T(d)
    end
end

"""
`CosSpace()` is the space spanned by `[1,cos θ,cos 2θ,...]`
"""
CosSpace()

"""
`SinSpace()` is the space spanned by `[sin θ,sin 2θ,...]`
"""
SinSpace()

# s == true means analytic inside, taylor series
# s == false means anlytic outside and decaying at infinity
"""
`Hardy{false}()` is the space spanned by `[1/z,1/z^2,...]`.
`Hardy{true}()` is the space spanned by `[1,z,z^2,...]`.
"""
struct Hardy{s,D<:PeriodicDomain,R} <: Space{D,R}
    domain::D
    Hardy{s,D,R}(d) where {s,D,R} = new{s,D,R}(d)
    Hardy{s,D,R}() where {s,D,R}  = new{s,D,R}(D())
end

# The <: PeriodicDomain is crucial for matching Basecall overrides
"""
`Taylor()` is the space spanned by `[1,z,z^2,...]`.
This is a type alias for `Hardy{true}`.
"""
const Taylor{D<:PeriodicDomain,R} = Hardy{true,D,R}


@containsconstants CosSpace
@containsconstants Taylor



Base.promote_rule(::Type{Fun{S,V}},::Type{T}) where {T<:Number,S<:Union{Hardy{true},CosSpace},V} =
    Fun{S,promote_type(V,T)}
Base.promote_rule(::Type{Fun{S}},::Type{T}) where {T<:Number,S<:Union{Hardy{true},CosSpace}} =
    Fun{S,T}

(H::Type{Hardy{s}})(d::PeriodicDomain) where {s} = Hardy{s,typeof(d),complex(prectype(d))}(d)
(H::Type{Hardy{s}})() where {s} = Hardy{s}(Circle())

canonicalspace(S::Hardy) = S
setdomain(S::Hardy{s},d::PeriodicDomain) where {s} = Hardy{s}(d)


spacescompatible(a::Hardy{s},b::Hardy{s}) where {s} = domainscompatible(a,b)
hasfasttransform(::Hardy) = true


for (Typ,Plfft!,Plfft,Pltr!,Pltr) in ((:TransformPlan,:plan_fft!,:plan_fft,:plan_transform!,:plan_transform),
                           (:ITransformPlan,:plan_ifft!,:plan_ifft,:plan_itransform!,:plan_itransform))
    @eval begin
        $Pltr!(sp::Hardy,x::AbstractVector{T}) where {T<:Complex} = $Typ(sp,$Plfft!(x),Val{true})
        $Pltr!(::Hardy,x::AbstractVector{T}) where {T<:Real} =
            error("In place variants not possible with real data.")

        $Pltr(sp::Hardy,x::AbstractVector{T}) where {T<:Complex} = $Typ(sp,$Pltr!(sp,x),Val{false})
        function $Pltr(sp::Hardy,x::AbstractVector{T}) where T
            plan = $Pltr(sp,Array{Complex{T}}(undef,length(x))) # we can reuse vector in itransform
            $Typ{T,typeof(sp),false,typeof(plan)}(sp,plan)
        end

        *(P::$Typ{T,HS,false},vals::AbstractVector{T}) where {T<:Complex,HS<:Hardy} = P.plan*copy(vals)
        *(P::$Typ{T,HS,false},vals::AbstractVector{T}) where {T,HS<:Hardy} = P.plan*Vector{Complex{T}}(vals)
    end
end


*(P::TransformPlan{T,Hardy{true,DD,RR},true},vals::AbstractVector{T}) where {T,DD,RR} =
    lmul!(one(T)/length(vals),P.plan*vals)
*(P::ITransformPlan{T,Hardy{true,DD,RR},true},cfs::AbstractVector{T}) where {T,DD,RR} =
    lmul!(length(cfs),P.plan*cfs)
*(P::TransformPlan{T,Hardy{false,DD,RR},true},vals::AbstractVector{T}) where {T,DD,RR} =
    lmul!(one(T)/length(vals),reverse!(P.plan*vals))
*(P::ITransformPlan{T,Hardy{false,DD,RR},true},cfs::AbstractVector{T}) where {T,DD,RR} =
    lmul!(length(cfs),P.plan*reverse!(cfs))


transform(sp::Hardy,vals::AbstractVector,plan) = plan*vals
itransform(sp::Hardy,vals::AbstractVector,plan) = plan*vals

evaluate(f::AbstractVector,S::Taylor{D,R},z) where {D<:PeriodicDomain,R} = horner(f,fromcanonical(Circle(),tocanonical(S,z)))
function evaluate(f::AbstractVector,S::Taylor{D,R},z) where {D<:Circle,R}
    z=mappoint(S,Circle(),z)
    d=domain(S)
    horner(f,z)
end

function evaluate(f::AbstractVector,S::Hardy{false,D},z) where D<:PeriodicDomain
    z=mappoint(S,Circle(),z)
    z=1/z
    z*horner(f,z)
end
function evaluate(f::AbstractVector,S::Hardy{false,D},z) where D<:Circle
    z=mappoint(S,Circle(),z)
    z=1/z
    z*horner(f,z)
end


##TODO: fast routine

function horner(c::AbstractVector,kr::AbstractRange{Int},x)
    T = promote_type(eltype(c),eltype(x))
    if isempty(c)
        return zero(x)
    end

    ret = zero(T)
    @inbounds for k in reverse(kr)
        ret = muladd(x,ret,c[k])
    end

    ret
end

function horner(c::AbstractVector,kr::AbstractRange{Int},x::AbstractVector)
    n,T = length(x),promote_type(eltype(c),eltype(x))
    if isempty(c)
        return zero(x)
    end

    ret = zeros(T,n)
    @inbounds for k in reverse(kr)
        ck = c[k]
        @simd for i = 1:n
            ret[i] = muladd(x[i],ret[i],ck)
        end
    end

    ret
end

horner(c::AbstractVector,x) = horner(c,1:length(c),x)
horner(c::AbstractVector,x::AbstractArray) = horner(c,1:length(c),x)
horner(c::AbstractVector,kr::AbstractRange{Int},x::AbstractArray) = reshape(horner(c,kr,vec(x)),size(x))

## Cos and Sin space

points(sp::CosSpace,n) = points(domain(sp),2n-2)[1:n]




plan_transform(::CosSpace,x::AbstractVector) = plan_chebyshevtransform(x;kind=2)
plan_itransform(::CosSpace,x::AbstractVector) = plan_ichebyshevtransform(x;kind=2)
transform(::CosSpace,vals,plan) = plan*vals
itransform(::CosSpace,cfs,plan) = plan*cfs

clenshaw(::CosSpace, c::AbstractVector, x) = chebyshev_clenshaw(c, x)

clenshaw(sp::CosSpace, c::AbstractVector, x::AbstractArray) =
    clenshaw(c,x,ClenshawPlan(promote_type(eltype(c),eltype(x)),sp,length(c),length(x)))

clenshaw(c::AbstractVector, x::Vector, plan::ClenshawPlan{<:CosSpace}) = chebyshev_clenshaw(c,x,plan)


function evaluate(f::AbstractVector,S::CosSpace,t)
    if t ∈ domain(S)
        clenshaw(S,f,cos(tocanonical(S,t)))
    else
        zero(cfstype(f))
    end
end


points(sp::SinSpace,n)=points(domain(sp),2n+2)[2:n+1]

for (Typ,Pltr!,Pltr) in ((:TransformPlan,:plan_transform!,:plan_transform),
                         (:ITransformPlan,:plan_itransform!,:plan_itransform))
    @eval begin
        $Pltr!(sp::SinSpace{DD},x::AbstractVector{T}) where {DD,T<:fftwNumber} =
            $Typ(sp,plan_r2r!(x,RODFT00),Val{true})
        $Pltr(sp::SinSpace{DD},x::AbstractVector{T}) where {DD,T<:fftwNumber} =
            $Typ(sp,$Pltr!(sp,x),Val{false})
        $Pltr!(sp::SinSpace{DD},x::AbstractVector{T}) where {DD,T} =
            error("transform for SinSpace only implemented for fftwNumbers")
        $Pltr(sp::SinSpace{DD},x::AbstractVector{T}) where {DD,T} =
            error("transform for SinSpace only implemented for fftwNumbers")

        *(P::$Typ{T,SinSpace{D,R},false},vals::AbstractVector{T}) where {T,D,R} = P.plan*copy(vals)
    end
end


*(P::TransformPlan{T,SinSpace{DD,RR},true},vals::AbstractVector{T}) where {T,DD,RR} =
    lmul!(one(T)/(length(vals)+1),P.plan*vals)
*(P::ITransformPlan{T,SinSpace{DD,RR},true},cfs::AbstractVector{T}) where {T,DD,RR} =
    lmul!(one(T)/2,P.plan*cfs)


transform(sp::SinSpace,vals::AbstractVector,plan) = plan*vals
itransform(sp::SinSpace,vals::AbstractVector,plan) = plan*vals

evaluate(f::AbstractVector,S::SinSpace,t) = sineshaw(f,tocanonical(S,t))



## Laurent space
"""
`Laurent()` is the space spanned by the complex exponentials
```
    1,exp(-im*θ),exp(im*θ),exp(-2im*θ),…
```
See also `Fourier`.
"""
const Laurent{DD,RR} = SumSpace{Tuple{Hardy{true,DD,RR},Hardy{false,DD,RR}},DD,RR}


##FFT That interlaces coefficients

plan_transform!(sp::Laurent{DD,RR},x::AbstractVector{T}) where {DD,RR,T<:Complex} =
    TransformPlan(sp,plan_fft!(x),Val{true})
plan_itransform!(sp::Laurent{DD,RR},x::AbstractVector{T}) where {DD,RR,T<:Complex} =
    ITransformPlan(sp,plan_ifft!(x),Val{true})

plan_transform!(sp::Laurent{DD,RR},x::AbstractVector{T}) where {DD,RR,T} =
    error("In place variants not possible with real data.")
plan_itransform!(sp::Laurent{DD,RR},x::AbstractVector{T}) where {DD,RR,T} =
    error("In place variants not possible with real data.")


plan_transform(sp::Laurent{DD,RR},x::AbstractVector{T}) where {T<:Complex,DD,RR} =
    TransformPlan(sp,plan_transform!(sp,x),Val{false})
plan_itransform(sp::Laurent{DD,RR},x::AbstractVector{T}) where {T<:Complex,DD,RR} =
    ITransformPlan(sp,plan_itransform!(sp,x),Val{false})

function plan_transform(sp::Laurent{DD,RR},x::AbstractVector{T}) where {T,DD,RR}
    plan = plan_transform(sp,Array{Complex{T}}(undef, length(x))) # we can reuse vector in itransform
    TransformPlan{T,typeof(sp),false,typeof(plan)}(sp,plan)
end
function plan_itransform(sp::Laurent{DD,RR},x::AbstractVector{T}) where {T,DD,RR}
    plan = plan_itransform(sp,Array{Complex{T}}(undef, length(x))) # we can reuse vector in itransform
    ITransformPlan{T,typeof(sp),false,typeof(plan)}(sp,plan)
end

function *(P::TransformPlan{T,Laurent{DD,RR},true},vals::AbstractVector{T}) where {T,DD,RR}
    n = length(vals)
    vals = lmul!(inv(convert(T,n)),P.plan*vals)
    reverseeven!(interlace!(vals,1))
end

function *(P::ITransformPlan{T,Laurent{DD,RR},true},cfs::AbstractVector{T}) where {T,DD,RR}
    n = length(cfs)
    reverseeven!(cfs)
    cfs[:]=[cfs[1:2:end];cfs[2:2:end]]  # TODO: deinterlace!
    lmul!(n,cfs)
    P.plan*cfs
end

*(P::TransformPlan{T,Laurent{DD,RR},false},vals::AbstractVector{T}) where {T<:Complex,DD,RR} =
    P.plan*copy(vals)
*(P::TransformPlan{T,Laurent{DD,RR},false},vals::AbstractVector{T}) where {T,DD,RR} =
    P.plan*Vector{Complex{T}}(vals)
*(P::ITransformPlan{T,Laurent{DD,RR},false},vals::AbstractVector{T}) where {T<:Complex,DD,RR} =
    P.plan*copy(vals)
*(P::ITransformPlan{T,Laurent{DD,RR},false},vals::AbstractVector{T}) where {T,DD,RR} =
    P.plan*Vector{Complex{T}}(vals)


transform(::Laurent{DD,RR},vals,plan) where {DD,RR} = plan*vals
itransform(::Laurent{DD,RR},cfs,plan) where {DD,RR} = plan*cfs

transform(sp::Laurent{DD,RR},vals::AbstractVector) where {DD,RR} = plan_transform(sp,vals)*vals
itransform(sp::Laurent{DD,RR},cfs::AbstractVector) where {DD,RR} = plan_itransform(sp,cfs)*cfs


function evaluate(f::AbstractVector,S::Laurent{DD,RR},z) where {DD,RR}
    z = mappoint(domain(S),Circle(),z)
    invz = 1/z
    horner(f,1:2:length(f),z) + horner(f,2:2:length(f),invz).*invz
end


function Base.conj(f::Fun{Laurent{DD,RR}}) where {DD,RR}
    ncoefficients(f) == 0 && return f

    cfs = Array{cfstype(f)}(undef, iseven(ncoefficients(f)) ? ncoefficients(f)+1 : ncoefficients(f))
    cfs[1] = conj(f.coefficients[1])
    cfs[ncoefficients(f)] = 0
    for k=2:2:ncoefficients(f)-1
        cfs[k] = conj(f.coefficients[k+1])
    end
    for k=3:2:ncoefficients(f)+1
        cfs[k] = conj(f.coefficients[k-1])
    end
    Fun(space(f),cfs)
end

## Fourier space

"""
`Fourier()` is the space spanned by the trigonemtric polynomials
```
    1,sin(θ),cos(θ),sin(2θ),cos(2θ),…
```
See also `Laurent`.
"""
const Fourier{DD,RR} = SumSpace{Tuple{CosSpace{DD,RR},SinSpace{DD,RR}},DD,RR}

Laurent(d::PeriodicDomain) = Laurent{typeof(d),complex(prectype(d))}(d)
Fourier(d::PeriodicDomain) = Fourier{typeof(d),real(prectype(d))}(d)

for Typ in (:Laurent,:Fourier)
    @eval begin
        $Typ() = $Typ(PeriodicSegment())
        $Typ(d) = $Typ(convert(PeriodicDomain, d))

        hasfasttransform(::$Typ{D,R}) where {D,R} = true
    end
end


Laurent(S::Fourier{DD,RR}) where {DD,RR} = Laurent(domain(S))
Fourier(S::Laurent{DD,RR}) where {DD,RR} = Fourier(domain(S))

for T in (:CosSpace,:SinSpace)
    @eval begin
        # override default as canonicalspace must be implemented
        maxspace(::$T,::Fourier{D,R}) where {D,R} = NoSpace()
        maxspace(::Fourier{D,R},::$T) where {D,R} = NoSpace()
    end
end

points(sp::Fourier{D,R},n) where {D,R}=points(domain(sp),n)

struct IFourierTransformPlan{T,SP,PL} <: AbstractTransformPlan{T}
    space::SP
    plan::PL
    work::Vector{T}
end

plan_transform!(sp::Fourier{D,R},x::AbstractVector{T}) where {T<:fftwNumber,D,R} =
    TransformPlan(sp,plan_r2r!(x, R2HC),Val{true})
plan_itransform!(sp::Fourier{D,R},x::AbstractVector{T}) where {T<:fftwNumber,D,R} =
    IFourierTransformPlan(sp, plan_r2r!(x, HC2R), copy(x)) # copy(x) is workspace data

for (Typ,Pltr!,Pltr) in ((:TransformPlan,:plan_transform!,:plan_transform),
                         (:ITransformPlan,:plan_itransform!,:plan_itransform))
    @eval begin
        $Pltr(sp::Fourier{DD,RR},x::AbstractVector{T}) where {T<:fftwNumber,DD,RR} =
            $Typ(sp,$Pltr!(sp,x),Val{false})
        $Pltr!(sp::Fourier{DD,RR},x::AbstractVector{T}) where {T,DD,RR} =
            error("transform for Fourier only implemented for fftwNumbers")
        $Pltr(sp::Fourier{DD,RR},x::AbstractVector{T}) where {T,DD,RR} =
            error("transform for Fourier only implemented for fftwNumbers")

        *(P::$Typ{T,Fourier{DD,RR},false},vals::AbstractVector{T}) where {T,DD,RR} = P.plan*copy(vals)
        *(P::$Typ{T,Fourier{DD,RR},false},vals::AbstractVector{<:Complex}) where {T,DD,RR} =
                P.plan*real(vals) .+ im.*(P.plan*imag(vals))
    end
end

mul!(cfs::AbstractVector{T}, P::TransformPlan{T,Fourier{DD,RR},true}, vals::AbstractVector{T}) where {T,DD,RR} =
    P*copyto!(cfs, vals)

mul!(cfs::AbstractVector{T}, P::TransformPlan{T,Fourier{DD,RR},false}, vals::AbstractVector{T}) where {T,DD,RR} =
    P.plan*copyto!(cfs, vals)

function *(P::TransformPlan{T,Fourier{DD,RR},true},vals::AbstractVector{T}) where {T,DD,RR}
    n = length(vals)
    cfs = lmul!(convert(T,2)/n,P.plan*vals)
    cfs[1] /= 2
    if iseven(n)
        cfs[n÷2+1] /= 2
    end

    negateeven!(reverseeven!(interlace!(cfs,1)))
end

mul!(vals::AbstractVector{T}, P::IFourierTransformPlan{T,Fourier{DD,RR}}, cfs::AbstractVector{T}) where {T,DD,RR} =
    P*copyto!(vals, cfs)

mul!(vals::AbstractVector{T}, P::ITransformPlan{T,Fourier{DD,RR},false},cfs::AbstractVector{T}) where {T,DD,RR} =
    mul!(vals, P.plan, cfs)

function *(P::IFourierTransformPlan{T,Fourier{DD,RR}},cfs::AbstractVector{T}) where {T,DD,RR}
    n = length(cfs)
    reverseeven!(negateeven!(cfs))

    # allocation free version of
    #    cfs[:] = [view(cfs,1:2:n); view(cfs, 2:2:n)]
    P.work .= cfs
    j = 1
    for k=1:2:n
        cfs[j] = P.work[k]
        j+=1
    end
    for k=2:2:n
        cfs[j] = P.work[k]
        j+=1
    end

    if iseven(n)
        cfs[n÷2+1] *= 2
    end
    cfs[1] *= 2
    P.plan*lmul!(inv(convert(T,2)),cfs)
end


transform(sp::Fourier{DD,RR},vals::AbstractVector,plan) where {DD,RR} = plan*vals
itransform(sp::Fourier{DD,RR},cfs::AbstractVector,plan) where {DD,RR} = plan*cfs

transform(sp::Fourier{DD,RR},vals::AbstractVector) where {DD,RR} = plan_transform(sp,vals)*vals
itransform(sp::Fourier{DD,RR},cfs::AbstractVector) where {DD,RR} = plan_itransform(sp,cfs)*cfs





canonicalspace(S::Laurent{DD,RR}) where {DD<:PeriodicSegment,RR} = Fourier(domain(S))
canonicalspace(S::Fourier{DD,RR}) where {DD<:Circle,RR} = Laurent(domain(S))
canonicalspace(S::Laurent{DD,RR}) where {DD<:PeriodicLine,RR} = S


## Ones and zeros

for sp in (:Fourier,:CosSpace,:Laurent,:Taylor)
    @eval begin
        one(::Type{T},S::$sp{DD,RR}) where {T<:Number,DD,RR} = Fun(S,fill(one(T),1))
        one(S::$sp{DD,RR}) where {DD,RR} = Fun(S,fill(1.0,1))
    end
end


function Fun(::typeof(identity), S::Taylor{DD,RR}) where {DD<:Circle,RR}
    d=domain(S)
    if d.orientation
        Fun(S,[d.center,d.radius])
    else
        error("Cannot create identity on $S")
    end
end


Fun(::typeof(identity), S::Fourier{DD,RR}) where {DD<:Circle,RR} =
    Fun(Fun(identity, Laurent(domain(S))),S)


reverseorientation(f::Fun{Fourier{DD,RR}}) where {DD,RR} =
    Fun(Fourier(reverseorientation(domain(f))),alternatesign!(copy(f.coefficients)))
function reverseorientation(f::Fun{Laurent{DD,RR}}) where {DD,RR}
    # exp(im*k*x) -> exp(-im*k*x), or equivalentaly z -> 1/z
    n=ncoefficients(f)
    ret=Array{cfstype(f)}(undef, iseven(n) ? n+1 : n)  # since z -> 1/z we get one more coefficient
    ret[1]=f.coefficients[1]
    for k=2:2:length(ret)-1
        ret[k+1]=f.coefficients[k]
    end
    for k=2:2:n-1
        ret[k]=f.coefficients[k+1]
    end
    iseven(n) && (ret[n] = 0)

    Fun(Laurent(reverseorientation(domain(f))),ret)
end

include("calculus.jl")
include("specialfunctions.jl")
include("FourierOperators.jl")
include("LaurentOperators.jl")
include("LaurentDirichlet.jl")
include("roots.jl")

Fun(::typeof(identity), d::Circle) = Fun(Laurent(d),[d.center,0.,d.radius])

Space(d::PeriodicDomain) = Fourier(d)
Space(d::Circle) = Laurent(d)


## Evaluation

Evaluation(d::PeriodicDomain,x::Number,n...) = Evaluation(Laurent(d),complex(x),n...)

## Definite Integral

DefiniteIntegral(d::PeriodicDomain) = DefiniteIntegral(Laurent(d))
DefiniteLineIntegral(d::PeriodicDomain) = DefiniteLineIntegral(Laurent(d))

## Toeplitz
union_rule(A::Space{<:PeriodicSegment}, B::Space{<:IntervalOrSegment}) =
    union(Space(Interval(domain(A))), B)


    ## Derivative

function invfromcanonicalD(S::Laurent{PeriodicLine{false}})
    d=domain(S)
    @assert d.center==0  && d.L==1.0
    a=Fun(Laurent(),[1.,.5,.5])
end

function invfromcanonicalD(S::LaurentDirichlet{PeriodicLine{false}})
    d=domain(S)
    @assert d.center==0  && d.L==1.0
    a=Fun(Laurent(),[1.,.5,.5])
end

Space(d::PeriodicCurve{S}) where {S<:Fourier} = Fourier(d)
Space(d::PeriodicCurve{S}) where {S<:Laurent} = Laurent(d)

function Fun(T::ToeplitzOperator)
    if length(T.nonnegative)==1
       Fun(Taylor(),[T.nonnegative;T.negative])
     elseif length(T.negative)==0
         Fun(Hardy{false}(),T.nonnegative)
     else
         Fun(Laurent(Circle()),interlace(T.nonnegative,T.negative))
     end
 end
 

end #module
