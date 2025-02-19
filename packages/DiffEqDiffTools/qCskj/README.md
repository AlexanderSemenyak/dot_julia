# DiffEqDiffTools

[![Join the chat at https://gitter.im/JuliaDiffEq/Lobby](https://badges.gitter.im/JuliaDiffEq/Lobby.svg)](https://gitter.im/JuliaDiffEq/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

[![Build Status](https://travis-ci.org/JuliaDiffEq/DiffEqDiffTools.jl.svg?branch=master)](https://travis-ci.org/JuliaDiffEq/DiffEqDiffTools.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/t3risc94d2jqipd6?svg=true)](https://ci.appveyor.com/project/ChrisRackauckas/diffeqdifftools-jl)
[![Coverage Status](https://coveralls.io/repos/JuliaDiffEq/DiffEqDiffTools.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaDiffEq/DiffEqDiffTools.jl?branch=master)
[![codecov.io](http://codecov.io/github/JuliaDiffEq/DiffEqDiffTools.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaDiffEq/DiffEqDiffTools.jl?branch=master)

DiffEqDiffTools.jl is a component package in the DifferentialEquations ecosystem.
It holds the common tools for taking derivatives, gradients, Jacobians, Hessians,
etc. This library is for maximizing speed while giving a usable interface to
end users. Included is:

- Fully non-allocating mutable forms for fast array support
- Fully non-mutating forms for static array support
- Coloring vectors for efficient calculation of sparse Jacobians

If you want the fastest versions, create a cache and repeatedly call the
differencing functions at different `x` values (or with different `f` functions),
while if you want a quick and dirty numerical answer, directly call a differencing
function.

## General Structure

The general structure of the library is as follows. You can call the differencing
functions directly and this will allocate a temporary cache to solve the problem
with. To make this non-allocating for repeat calls, you can call the cache
construction functions. Each cache construction function has two possibilities:
one version where you give it prototype arrays and it generates the cache
variables, and one fully non-allocating version where you give it the cache
variables. This is summarized as:

- Just want a quick derivative? Calculating once? Call the differencing function.
- Going to calculate the derivative multiple times but don't have cache arrays
  around? Use the allocating cache and then pass this into the differencing
  function (this will allocate only in the one cache construction).
- Have cache variables around from your own algorithm and want to re-use them
  in the differencing functions? Use the non-allocating cache construction
  and pass the cache to the differencing function.

## f Definitions

In all functions, the inplace form is `f!(dx,x)` while the out of place form is `dx = f(x)`.

## colorvec Vectors

colorvec vectors are allowed to be supplied to the Jacobian routines, and these are
the directional derivatives for constructing the Jacobian. For example, an accurate
NxN tridiagonal Jacobian can be computed in just 4 `f` calls by using
`colorvec=repeat(1:3,N÷3)`. For information on automatically generating colorvec
vectors of sparse matrices, see [SparseDiffTools.jl](https://github.com/JuliaDiffEq/SparseDiffTools.jl).

Hessian coloring support is coming soon!

## Scalar Derivatives

```julia
DiffEqDiffTools.finite_difference_derivative(f, x::T, fdtype::Type{T1}=Val{:central},
    returntype::Type{T2}=eltype(x), f_x::Union{Nothing,T}=nothing)
```

## Multi-Point Derivatives

### Differencing Calls

```julia
# Cache-less but non-allocating if `fx` and `epsilon` are supplied
# fx must be f(x)
DiffEqDiffTools.finite_difference_derivative(
    f,
    x          :: AbstractArray{<:Number},
    fdtype     :: Type{T1} = Val{:central},
    returntype :: Type{T2} = eltype(x),      # return type of f
    fx         :: Union{Nothing,AbstractArray{<:Number}} = nothing,
    epsilon    :: Union{Nothing,AbstractArray{<:Real}} = nothing;
    [epsilon_factor])

DiffEqDiffTools.finite_difference_derivative!(
    df         :: AbstractArray{<:Number},
    f,
    x          :: AbstractArray{<:Number},
    fdtype     :: Type{T1} = Val{:central},
    returntype :: Type{T2} = eltype(x),
    fx         :: Union{Nothing,AbstractArray{<:Number}} = nothing,
    epsilon    :: Union{Nothing,AbstractArray{<:Real}}   = nothing;
    [epsilon_factor])

# Cached
DiffEqDiffTools.finite_difference_derivative!(
    df::AbstractArray{<:Number},
    f,
    x::AbstractArray{<:Number},
    cache::DerivativeCache{T1,T2,fdtype,returntype};
    [epsilon_factor])
```

### Allocating and Non-Allocating Constructor

```julia
DiffEqDiffTools.DerivativeCache(
    x          :: AbstractArray{<:Number},
    fx         :: Union{Nothing,AbstractArray{<:Number}} = nothing,
    epsilon    :: Union{Nothing,AbstractArray{<:Real}} = nothing,
    fdtype     :: Type{T1} = Val{:central},
    returntype :: Type{T2} = eltype(x))
```

This allocates either `fx` or `epsilon` if these are nothing and they are needed.
`fx` is the current call of `f(x)` and is required for forward-differencing
(otherwise is not necessary).

## Gradients

Gradients are either a vector->scalar map `f(x)`, or a scalar->vector map
`f(fx,x)` if `inplace=Val{true}` and `fx=f(x)` if `inplace=Val{false}`.

### Differencing Calls

```julia
# Cache-less
DiffEqDiffTools.finite_difference_gradient(
    f,
    x,
    fdtype::Type{T1}=Val{:central},
    returntype::Type{T2}=eltype(x),
    inplace::Type{Val{T3}}=Val{true};
    [epsilon_factor])
DiffEqDiffTools.finite_difference_gradient!(
    df,
    f,
    x,
    fdtype::Type{T1}=Val{:central},
    returntype::Type{T2}=eltype(df),
    inplace::Type{Val{T3}}=Val{true};
    [epsilon_factor])

# Cached
DiffEqDiffTools.finite_difference_gradient!(
    df::AbstractArray{<:Number},
    f,
    x::AbstractArray{<:Number},
    cache::GradientCache;
    [epsilon_factor])
```

### Allocating Cache Constructor

```julia
DiffEqDiffTools.GradientCache(
    df         :: Union{<:Number,AbstractArray{<:Number}},
    x          :: Union{<:Number, AbstractArray{<:Number}},
    fdtype     :: Type{T1} = Val{:central},
    returntype :: Type{T2} = eltype(df),
    inplace    :: Type{Val{T3}} = Val{true})
```

### Non-Allocating Cache Constructor

```julia
DiffEqDiffTools.GradientCache(
    c1         :: Union{Nothing,AbstractArray{<:Number}},
    c2         :: Union{Nothing,AbstractArray{<:Number}},
    fx         :: Union{Nothing,<:Number,AbstractArray{<:Number}} = nothing,
    fdtype     :: Type{T1} = Val{:central},
    returntype :: Type{T2} = eltype(df),
    inplace    :: Type{Val{T3}} = Val{true})
```

Note that here `fx` is a cached function call of `f`. If you provide `fx`, then
`fx` will be used in the forward differencing method to skip a function call.
It is on you to make sure that you update `cache.fx` every time before
calling `DiffEqDiffTools.finite_difference_gradient!`. A good use of this is if you have a
cache array for the output of `fx` already being used, you can make it alias
into the differencing algorithm here.

## Jacobians

Jacobians are for functions `f!(fx,x)` when `inplace=Val{true}`, and `fx = f(x)`
when `inplace=Val{false}`. For non-square Jacobians, a cache which specifies the
vector `fx` is required.

### Differencing Calls

```julia
# Cache-less
DiffEqDiffTools.finite_difference_jacobian(
    f,
    x          :: AbstractArray{<:Number},
    fdtype     :: Type{T1}=Val{:central},
    returntype :: Type{T2}=eltype(x),
    inplace    :: Type{Val{T3}}=Val{true};
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = eachindex(x),
    sparsity = nothing)

finite_difference_jacobian!(J::AbstractMatrix,
    f,
    x::AbstractArray{<:Number},
    fdtype     :: Type{T1}=Val{:forward},
    returntype :: Type{T2}=eltype(x),
    inplace    :: Type{Val{T3}}=Val{true},
    f_in       :: Union{T2,Nothing}=nothing;
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = eachindex(x),
    sparsity = J isa SparseMatrixCSC ? J : nothing)

# Cached
DiffEqDiffTools.finite_difference_jacobian(
    f,
    x,
    cache::JacobianCache;
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = eachindex(x),
    sparsity = nothing)

DiffEqDiffTools.finite_difference_jacobian!(
    J::AbstractMatrix{<:Number},
    f,
    x::AbstractArray{<:Number},
    cache::JacobianCache;
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep,
    colorvec = cache.colorvec,
    sparsity = cache.sparsity)
```

### Allocating Cache Constructor

```julia
DiffEqDiffTools.JacobianCache(
              x,
              fdtype     :: Type{T1} = Val{:central},
              returntype :: Type{T2} = eltype(x),
              inplace    :: Type{Val{T3}} = Val{true};
              colorvec = eachindex(x)
              sparsity = nothing)
```

This assumes the Jacobian is square.

### Non-Allocating Cache Constructor

```julia
DiffEqDiffTools.JacobianCache(
              x1 ,
              fx ,
              fx1,
              fdtype     :: Type{T1} = Val{:central},
              returntype :: Type{T2} = eltype(fx),
              inplace    :: Type{Val{T3}} = Val{true};
              colorvec = eachindex(x),
              sparsity = nothing)
```

## Hessians

Hessians are for functions `f(x)` which return a scalar.

### Differencing Calls

```julia
#Cacheless
finite_difference_hessian(f, x::AbstractArray{<:Number},
    fdtype     :: Type{T1}=Val{:hcentral},
    inplace    :: Type{Val{T2}} = x isa StaticArray ? Val{true} : Val{false};
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep)

finite_difference_hessian!(H::AbstractMatrix,f,
    x::AbstractArray{<:Number},
    fdtype     :: Type{T1}=Val{:hcentral},
    inplace    :: Type{Val{T2}} = x isa StaticArray ? Val{true} : Val{false};
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep)

#Cached
finite_difference_hessian(
    f,x,
    cache::HessianCache{T,fdtype,inplace};
    relstep=default_relstep(fdtype, eltype(x)),
    absstep=relstep)

finite_difference_hessian!(H,f,x,
                           cache::HessianCache{T,fdtype,inplace};
                           relstep = default_relstep(fdtype, eltype(x)),
                           absstep = relstep)
```

### Allocating Cache Calls

```julia
HessianCache(x,fdtype::Type{T1}=Val{:hcentral},
                        inplace::Type{Val{T2}} = x isa StaticArray ? Val{true} : Val{false})
```

### Non-Allocating Cache Calls

```julia
HessianCache(xpp,xpm,xmp,xmm,
                      fdtype::Type{T1}=Val{:hcentral},
                      inplace::Type{Val{T2}} = x isa StaticArray ? Val{true} : Val{false})
```
