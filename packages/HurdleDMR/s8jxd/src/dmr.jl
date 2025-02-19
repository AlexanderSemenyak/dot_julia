##############################################################
# Distributed Multinomial Regression (DMR)
##############################################################

"Abstract Distributed Counts Regression (DCR) returned object"
abstract type DCR <: RegressionModel end

"Abstract DMR returned object"
abstract type DMR <: DCR end

"""
Relatively heavy object used to return DMR results when we care about the regulatrization paths.
"""
struct DMRPaths <: DMR
  nlpaths::Vector{Union{Missing,GammaLassoPath}} # independent Poisson GammaLassoPath for each phrase
  intercept::Bool               # whether to include an intercept in each Poisson regression
                                # (only kept with remote cluster, not with local cluster)
  n::Int                      # number of observations. May be lower than provided after removing all zero obs.
  d::Int                      # number of categories (terms/words/phrases)
  p::Int                      # number of covariates

  DMRPaths(nlpaths::Vector{Union{Missing,GammaLassoPath}}, intercept::Bool,
    n::Int, d::Int, p::Int) =
    new(nlpaths, intercept, n, d, p)
end

"""
Relatively light object used to return DMR results when we only care about estimated coefficients.
"""
struct DMRCoefs <: DMR
  coefs::AbstractMatrix         # model coefficients
  intercept::Bool               # whether to include an intercept in each Poisson regression
  n::Int                      # number of observations. May be lower than provided after removing all zero obs.
  d::Int                      # number of categories (terms/words/phrases)
  p::Int                      # number of covariates
  select::Symbol              # path segment selector

  DMRCoefs(coefs::AbstractMatrix, intercept::Bool, n::Int, d::Int, p::Int, select::Symbol) =
    new(coefs, intercept, n, d, p, select)

  function DMRCoefs(m::DMRPaths; select=:AICc)
    coefs = coef(m; select=select)
    new(coefs, m.intercept, m.n, m.d, m.p, select)
  end
end

"""
    fit(DMR,covars,counts; <keyword arguments>)
    dmr(covars,counts; <keyword arguments>)

Fit a Distributed Multinomial Regression (DMR) of counts on covars.

DMR fits independent poisson gamma lasso regressions to each column of counts to
approximate a multinomial, picks a segement of each path, and
returns a coefficient matrix (wrapped in DMRCoefs) representing point estimates
for the entire multinomial (includes the intercept if one was included).

# Example:
```julia
  m = fit(DMR,covars,counts)
```
# Arguments
- `covars` n-by-p matrix of covariates
- `counts` n-by-d matrix of counts (usually sparse)

# Keywords
- `intercept::Bool=false` include an intercept in each poisson
- `parallel::Bool=true` parallelize the poisson fits
- `local_cluster::Bool=true` use local_cluster mode that shares memory across
    parallel workers that is appropriate on a single multicore machine, or
    remote cluster mode that is more appropriate when distributing across machines
    for which sharing memory is costly.
- `verbose::Bool=true`
- `showwarnings::Bool=false`
- `select::Symbol=:AICc` which path segment to pick
- `kwargs...` additional keyword arguments passed along to fit(GammaLassoPath,...)
"""
function StatsBase.fit(::Type{D}, covars::AbstractMatrix{T}, counts::AbstractMatrix;
  kwargs...) where {T<:AbstractFloat, D<:DMR}

  dmr(covars, counts; kwargs...)
end

"""
    fit(DMRPaths,covars,counts; <keyword arguments>)
    dmrpaths(covars,counts; <keyword arguments>)

Fit a Distributed Multinomial Regression (DMR) of counts on covars, and returns
the entire regulatrization paths, which may be useful for plotting or picking
coefficients other than the AICc optimal ones. Same arguments as [`fit(::DMR)`](@ref).
"""
function StatsBase.fit(::Type{DMRPaths}, covars::AbstractMatrix{T}, counts::AbstractMatrix;
  local_cluster=false, # ignored. will always assume remote_cluster
  kwargs...) where {T<:AbstractFloat}

  dmrpaths(covars, counts; kwargs...)
end

"""
    fit(DMR,@model(c ~ x1*x2),df,counts; <keyword arguments>)

Fits a DMR but takes a model formula and dataframe instead of the covars matrix.
See also [`fit(::DMR)`](@ref).

`c` must be specified on the lhs to indicate the model for counts.
"""
function StatsBase.fit(::Type{T}, m::Model, df::AbstractDataFrame, counts::AbstractMatrix;
  contrasts::Dict = Dict(), kwargs...) where {T<:DMR}

  # parse and merge rhs terms
  trms = getrhsterms(m, :c)

  # create model matrix
  mf, mm, counts = createmodelmatrix(trms, df, counts, contrasts)

  # fit and wrap in DataFrameRegressionModel
  StatsModels.DataFrameRegressionModel(fit(T, mm.m, counts; kwargs...), mf, mm)
end

"""
    coef(m::DMRCoefs)

Returns the AICc optimal coefficients matrix fitted with DMR.

# Example:
```julia
  m = fit(DMR,covars,counts)
  coef(m)
```
"""
function StatsBase.coef(m::DMRCoefs; select=m.select)
  if select == m.select
    m.coefs
  else
    error("coef(m::DMRCoefs) supports only the regulatrization path segement
      selector $(m.select) specified during fit().")
  end
end

"""
    coef(m::DMRPaths; select=:AICc)

Returns all or selected coefficients matrix fitted with DMR.

# Example:
```julia
  m = fit(DMRPaths,covars,counts)
  coef(m; select=:CVmin)
```

# Keywords
- `select=:AICc` See [`coef(::RegularizationPath)`](@ref).
"""
function StatsBase.coef(m::DMRPaths; select=:AICc)
  # get dims
  d = length(m.nlpaths)
  d < 1 && return nothing

  # drop missing paths
  nonmsngpaths = skipmissing(m.nlpaths)

  # get number of coefs from paths object
  p = ncoefs(m)

  # establish maximum path lengths
  nλ = 0
  if !isempty(nonmsngpaths)
    nλ = maximum(size(nlpath)[2] for nlpath in nonmsngpaths)
  end

  # allocate space
  if select==:all
    coefs = zeros(nλ,p,d)
  else
    coefs = zeros(p,d)
  end

  # iterate over paths
  for j=1:d
    path = m.nlpaths[j]
    if !ismissing(path)
      cj = coef(path;select=select)
      if select==:all
        for i=1:p
          for s=1:size(cj,2)
            coefs[s,i,j] = cj[i,s]
          end
        end
      else
        for i=1:p
          coefs[i,j] = cj[i]
        end
      end
    end
  end

  coefs
end

"Whether the model includes an intercept in each independent counts (e.g. hurdle) regression"
hasintercept(m::DCR) = m.intercept

"Number of observations used. May be lower than provided after removing all zero obs."
StatsBase.nobs(m::DCR) = m.n

"Number of categories (terms/words/phrases) used for DMR estimation"
Distributions.ncategories(m::DCR) = m.d

"Number of covariates used for DMR estimation"
ncovars(m::DMR) = m.p

"Number of coefficient potentially including intercept used for each independent Poisson regression"
ncoefs(m::DMR) = ncovars(m) + (hasintercept(m) ? 1 : 0)

# some helpers for converting to SharedArray
Base.convert(::Type{SharedArray}, A::SubArray) = (S = SharedArray{eltype(A)}(size(A)); copyto!(S, A))
function Base.convert(::Type{SharedArray}, A::SparseMatrixCSC{T,N}) where {T,N}
  S = SharedArray{T}(size(A))
  fill!(S,zero(T))
  rows = rowvals(A)
  vals = nonzeros(A)
  n, m = size(A)
  for j = 1:m
     for i in nzrange(A, j)
        row = rows[i]
        val = vals[i]
        S[row,j] = val
     end
  end
  S
end

"convert counts matrix elements to Float64 if necessary"
fpcounts(counts::M) where {V, N, M<:SparseMatrixCSC{V,N}} = convert(SparseMatrixCSC{Float64,N}, counts)
fpcounts(counts::M) where {V, M<:AbstractMatrix{V}} = convert(Matrix{Float64}, counts)
fpcounts(counts::M) where {V<:GLM.FP, N, M<:SparseMatrixCSC{V,N}} = counts
fpcounts(counts::M) where {V<:GLM.FP, M<:AbstractMatrix{V}} = counts

"Computes DMR shifters (μ=log(m)) and removes all zero observations"
function shifters(covars::AbstractMatrix{T}, counts::AbstractMatrix{C}, showwarnings::Bool) where {T<:AbstractFloat,C}
    # standardize counts matrix to conform to GLM.FP
    counts = fpcounts(counts)

    m = vec(sum(counts, dims=2))

    if any(iszero,m)
        # omit observations with no counts
        ixposm = findall(x->x!=zero(C), m)
        showwarnings && @warn("omitting $(length(m)-length(ixposm)) observations with no counts")
        m = m[ixposm]
        counts = counts[ixposm,:]
        covars = covars[ixposm,:]
    end

    μ = log.(m)

    n = length(m)

    covars, counts, μ, n
end

"""
This version is built for local clusters and shares memory used by both inputs and outputs if run in parallel mode.
"""
function dmr_local_cluster(covars::AbstractMatrix{T},counts::AbstractMatrix{V},
          parallel,verbose,showwarnings,intercept; select=:AICc, kwargs...) where {T<:AbstractFloat,V}
  # get dimensions
  n, d = size(counts)
  n1,p = size(covars)
  @assert n==n1 "counts and covars should have the same number of observations"
  verbose && @info("fitting $n observations on $d categories, $p covariates ")

  # add one coef for intercept
  ncoef = p + (intercept ? 1 : 0)

  covars, counts, μ, n = shifters(covars, counts, showwarnings)

  # fit separate GammaLassoPath's to each dimension of counts j=1:d and pick its min AICc segment
  if parallel
    verbose && @info("distributed poisson run on local cluster with $(nworkers()) nodes")
    counts = convert(SharedArray,counts)
    coefs = SharedMatrix{T}(ncoef,d)
    covars = convert(SharedArray,covars)
    # μ = convert(SharedArray,μ) incompatible with GLM

    @sync @distributed for j=1:d
      tryfitgl!(coefs, j, covars, counts; offset=μ, verbose=false,
        showwarnings=showwarnings, intercept=intercept, select=select, kwargs...)
    end
  else
    verbose && @info("serial poisson run on a single node")
    coefs = Matrix{T}(undef,ncoef,d)
    for j=1:d
      tryfitgl!(coefs, j, covars, counts; offset=μ, verbose=false,
        showwarnings=showwarnings, intercept=intercept, select=select, kwargs...)
    end
  end

  DMRCoefs(coefs, intercept, n, d, p, select)
end

"This version does not share memory across workers, so may be more efficient for small problems, or on remote clusters."
function dmr_remote_cluster(covars::AbstractMatrix{T},counts::AbstractMatrix{V},
          parallel,verbose,showwarnings,intercept; select=:AICc, kwargs...) where {T<:AbstractFloat,V}
  paths = dmrpaths(covars, counts; parallel=parallel, verbose=verbose, showwarnings=showwarnings, intercept=intercept, kwargs...)
  DMRCoefs(paths; select=select)
end

"Shorthand for fit(DMRPaths,covars,counts). See also [`fit(::DMRPaths)`](@ref)"
function dmrpaths(covars::AbstractMatrix{T},counts::AbstractMatrix;
      intercept=true,
      parallel=true,
      verbose=true, showwarnings=false,
      kwargs...) where {T<:AbstractFloat}
  # get dimensions
  n, d = size(counts)
  n1,p = size(covars)
  @assert n==n1 "counts and covars should have the same number of observations"
  verbose && @info("fitting $n observations on $d categories, $p covariates ")

  covars, counts, μ, n = shifters(covars, counts, showwarnings)

  function tryfitgl(countsj::AbstractVector)
    try
      # we make it dense remotely to reduce communication costs
      fit(GammaLassoPath,covars,Vector(countsj),Poisson(),LogLink(); offset=μ, verbose=false, kwargs...)
    catch e
      showwarnings && @warn("fitgl failed for countsj with frequencies $(sort(countmap(countsj))) and will return missing path ($e)")
      missing
    end
  end

  # counts generator
  countscols = (counts[:,j] for j=1:d)

  if parallel
    verbose && @info("distributed poisson run on remote cluster with $(nworkers()) nodes")
    mapfn = pmap
  else
    verbose && @info("serial poisson run on a single node")
    mapfn = map
  end

  # TODO: the conversion here may be redudant
  nlpaths = convert(Vector{Union{Missing,GammaLassoPath}},mapfn(tryfitgl,countscols))

  DMRPaths(nlpaths, intercept, n, d, p)
end

"Fits a regularized poisson regression counts[:,j] ~ covars saving the coefficients in coefs[:,j]"
function poisson_regression!(coefs::AbstractMatrix{T}, j::Int, covars::AbstractMatrix{T},counts::AbstractMatrix{V};
  select=:AICc, kwargs...) where {T<:AbstractFloat,V}
  cj = Vector(counts[:,j])
  path = fit(GammaLassoPath,covars,cj,Poisson(),LogLink(); kwargs...)
  coefs[:,j] = coef(path; select=select)
  nothing
end

"Wrapper for poisson_regression! that catches exceptions in which case it sets coefs to zero"
function tryfitgl!(coefs::AbstractMatrix{T}, j::Int, covars::AbstractMatrix{T},counts::AbstractMatrix{V};
            showwarnings = false,
            kwargs...) where {T<:AbstractFloat,V}
  try
    poisson_regression!(coefs, j, covars, counts; kwargs...)
  catch e
    showwarnings && @warn("fitgl! failed on count dimension $j with frequencies $(sort(countmap(counts[:,j]))) and will return zero coefs ($e)")
    # redudant ASSUMING COEFS ARRAY INTIAILLY FILLED WITH ZEROS, but can be uninitialized in serial case
    for i=1:size(coefs,1)
      coefs[i,j] = zero(T)
    end
  end
end

"Shorthand for fit(DMR,covars,counts). See also [`fit(::DMR)`](@ref)"
function dmr(covars::AbstractMatrix{T},counts::AbstractMatrix{V};
          intercept=true,
          parallel=true, local_cluster=true,
          verbose=true, showwarnings=false,
          kwargs...) where {T<:AbstractFloat,V}
  if local_cluster || !parallel
    dmr_local_cluster(covars,counts,parallel,verbose,showwarnings,intercept; kwargs...)
  else
    dmr_remote_cluster(covars,counts,parallel,verbose,showwarnings,intercept; kwargs...)
  end
end

# We take care of the intercept ourselves, without relying on StatsModels, because
# it is unregulated, so we drop it from formula
StatsModels.drop_intercept(::Type{T}) where {T<:DCR} = true

# delegate f(m::DataFrameRegressionModel,...) to f(m.model,...)
StatsModels.@delegate StatsModels.DataFrameRegressionModel.model [hasintercept, Distributions.ncategories, ncovars, ncoefs, ncovarszero, ncovarspos, ncoefszero, ncoefspos]

"""
    predict(m,newcovars; <keyword arguments>)

Predict counts using a fitted DMRPaths object and given newcovars.

# Example:
```julia
  m = fit(DMRPaths,covars,counts)
  newcovars = covars[1:10,:]
  countshat = predict(m, newcovars; select=:AICc)
```

# Arguments
- `m::DMRPaths` fitted DMRPaths model (DMRCoefs currently not supported)
- `newcovars` n-by-p matrix of covariates of same dimensions used to fit m.

# Keywords
- `select=:AICc` See [`coef(::RegularizationPath)`](@ref).
- `kwargs...` additional keyword arguments passed along to predict() for each
  category j=1..size(counts,2)
"""
function StatsBase.predict(m::DMRPaths, newcovars::AbstractMatrix{T};
  select=:AICc, kwargs...) where {T<:AbstractFloat}

  _predict(m,newcovars;select=select,kwargs...)
end

# internal mothod used by both dmr and hdmr
function _predict(m, newcovars::AbstractMatrix{T};
  select=:AICc, kwargs...) where {T<:AbstractFloat}

  @assert select != :all "select cannot be :all and must choose a particular segment (e.g. select=:AICc)"

  # dimensions
  newn = size(newcovars,1)

  # offset does not matter here because we rescale in the end
  newoffset = zeros(T,size(newcovars,1))

  η = zeros(T,newn,m.d)
  for j=1:m.d
    path = m.nlpaths[j]
    if !ismissing(path)
      η[:,j] = predict(path, newcovars;offset=newoffset, select=select, kwargs...)
    end
  end

  lmul!(Diagonal(one(T)./vec(sum(η, dims=2))),η)

  η
end

function StatsBase.predict(m::M, newcovars::AbstractMatrix{T};
  select=:AICc, kwargs...) where {T<:AbstractFloat, M<:DMR}

  error("predict(m::DMR,...) can currently only be evaluated for DMRPaths structs returned from fit(DMRPaths,...)")
end
