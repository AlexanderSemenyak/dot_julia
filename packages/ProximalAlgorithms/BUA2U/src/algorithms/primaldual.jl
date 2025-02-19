# Latafat, Patrinos, "Asymmetric forward–backward–adjoint splitting for
# solving monotone inclusions involving three operators", Computational
# Optimization and Applications, vol. 68, no. 1, pp. 57-93 (2017).
#
# Chambolle, Pock, "A First-Order Primal-Dual Algorithm for Convex Problems
# with Applications to Imaging", Journal of Mathematical Imaging and Vision,
# vol. 40, no. 1, pp. 120-145 (2011).
#
# Condat, "A primal–dual splitting method for convex optimization
# involving Lipschitzian, proximable and linear composite terms",
# Journal of Optimization Theory and Applications, vol. 158, no. 2,
# pp 460-479 (2013).
# 
# Vũ, "A splitting algorithm for dual monotone inclusions involving
# cocoercive operators", Advances in Computational Mathematics, vol. 38, no. 3,
# pp. 667-681 (2013).

using Base.Iterators
using ProximalAlgorithms.IterationTools
using ProximalOperators: Zero
using LinearAlgebra
using Printf

struct AFBA_iterable{R, Tx, Ty, Tf, Tg, Th, Tl, TL}
    f::Tf
    g::Tg
    h::Th
    l::Tl
    L::TL
    x0::Tx
    y0::Ty
    theta::R
    mu::R
    lambda::R
    gamma1::R
    gamma2::R
end

struct AFBA_state{Tx, Ty}
    x::Tx
    y::Ty
    xbar::Tx
    ybar::Ty
    gradf::Tx
    gradl::Ty
    FPR_x::Tx
    FPR_y::Ty
    temp_x::Tx
    temp_y::Ty
end

AFBA_state(iter::AFBA_iterable) = AFBA_state(
    copy(iter.x0), copy(iter.y0),
    zero(iter.x0), zero(iter.y0),
    zero(iter.x0), zero(iter.y0),
    zero(iter.x0), zero(iter.y0),
    zero(iter.x0), zero(iter.y0)
)

function Base.iterate(iter::AFBA_iterable, state::AFBA_state=AFBA_state(iter))
    # perform xbar-update step
    gradient!(state.gradf, iter.f, state.x)
    mul!(state.temp_x, iter.L', state.y)
    state.temp_x .+= state.gradf
    state.temp_x .*= -iter.gamma1
    state.temp_x .+= state.x
    prox!(state.xbar, iter.g, state.temp_x, iter.gamma1)

    # perform ybar-update step
    gradient!(state.gradl, Conjugate(iter.l), state.y)
    state.temp_x .= iter.theta .* state.xbar .+ (1-iter.theta) .* state.x
    mul!(state.temp_y, iter.L, state.temp_x)
    state.temp_y .-= state.gradl
    state.temp_y .*= iter.gamma2
    state.temp_y .+= state.y
    prox!(state.ybar, Conjugate(iter.h), state.temp_y, iter.gamma2)

    # the residues
    state.FPR_x .= state.xbar .- state.x
    state.FPR_y .= state.ybar .- state.y

    # perform x-update step
    state.temp_y .= (iter.mu * (2-iter.theta) * iter.gamma1) .* state.FPR_y
    mul!(state.temp_x, iter.L', state.temp_y)
    state.x .+= iter.lambda .* (state.FPR_x .- state.temp_x)

    # perform y-update step
    state.temp_x .= ((1-iter.mu) * (2-iter.theta) * iter.gamma2) .* state.FPR_x
    mul!(state.temp_y, iter.L, state.temp_x)
    state.y .+= iter.lambda .* (state.FPR_y .+ state.temp_y)

    return state, state
end

function AFBA_default_stepsizes(L, h, theta::R, mu::R, betaQ::R, betaR::R) where {R <: Real}
    par = R(4) #  scale parameter for comparing Lipschitz constant and opnorm(L)
    nmL = R(opnorm(L))
    alpha = R(1)

    if isa(h, ProximalOperators.Zero)
        # mu=0 is the only case where stepsizes matter
        alpha = R(1000)/(betaQ+R(1e-5)) # the speed is determined by gamma1 since bary=0
        temp = theta^2-3*theta+R(3)
        gamma1 = R(0.99)/(betaQ/2 + temp*nmL/alpha) # in this case R=0
        gamma2 = R(1)/(nmL*alpha)
    else
        if theta==2 # default stepsize for Vu-Condat
            if betaQ > par*nmL && betaR > par*nmL
                alpha = R(1)
            elseif betaQ > par*nmL
                alpha = 2*nmL/betaQ
            elseif betaR > par*nmL
                alpha = betaR/(2*nmL)
            end
            gamma1 = R(1)/(betaQ/2+nmL/alpha)
            gamma2 = R(0.99)/(betaR/2+nmL*alpha)
        elseif theta == 1 && mu == 1 # default stepsize for theta=1, mu=1
            if betaQ > par*nmL && betaR > par*nmL
                alpha = R(1)
            elseif betaQ > par*nmL
                alpha = 2*nmL/betaQ
            elseif betaR > par*nmL
                alpha = betaR/(2*nmL)
            end
            gamma1 = R(1)/(betaQ/2+nmL/alpha)
            gamma2 = R(0.99)/(betaR/2 + gamma1*nmL^2)
        elseif theta == 0 && mu == 1 # default stepsize for theta=0, mu=1
            temp=3
            if betaQ > par*nmL && betaR > temp*par*nmL # denominator for Sigma involves 3α opnorm(L) in this case
                alpha = R(1)
            elseif betaQ > par*nmL
                alpha = 2*nmL/betaQ
            elseif betaR > temp*par*nmL # denominator for Sigma involves 3α opnorm(L) in this case
                alpha = betaR/(temp*2*nmL)
            end
            gamma1 = R(1)/(betaQ/2+nmL/alpha)
            gamma2 = R(0.99)/(betaR/2 + 2*gamma1*nmL^2 + alpha*nmL)
        elseif mu == 0 # default stepsize for  mu=0
            temp = theta^2-3*theta+3
            if betaQ > temp*par*nmL && betaR > par*nmL
                alpha = R(1)
            elseif betaR > par*nmL
                alpha = betaR/(2*nmL)
            elseif betaQ > temp*par*nmL # denominator for Sigma involves 3α opnorm(L) in this case
                alpha = 2*nmL*temp/betaQ
            end
            gamma2 = R(1)/(betaR/2+ alpha*nmL)
            gamma1 = R(0.99)/(betaQ/2 + (temp-1)*gamma2*nmL^2 + nmL/alpha)
        else
            error("this choice of theta and mu is not supported!")
        end
    end

    return gamma1, gamma2
end

# Solver

struct AFBA{R}
    gamma1::Maybe{R}
    gamma2::Maybe{R}
    theta::R
    mu::R
    lambda::R
    maxit::Int
    tol::R
    verbose::Bool
    freq::Int

    function AFBA{R}(; gamma1::Maybe{R}=nothing, gamma2::Maybe{R}=nothing,
        theta::R=R(1), mu::R=R(1), lambda::R=R(1), maxit::Int=10000,
        tol::R=R(1e-5), verbose::Bool=false, freq::Int=100
    ) where R
        @assert gamma1 === nothing || gamma > 0
        @assert gamma2 === nothing || gamma > 0
        @assert theta >= 0
        @assert 0 <= mu <= 1
        @assert lambda > 0
        @assert maxit > 0
        @assert tol > 0
        @assert freq > 0
        new(gamma1, gamma2, theta, mu, lambda, maxit, tol, verbose, freq)
    end
end

function (solver::AFBA{R})(x0::AbstractArray{C}, y0::AbstractArray{C};
    f=Zero(), g=Zero(), h=Zero(), l=IndZero(), L=I, betaQ::R=R(0), betaR::R=R(0)
) where {R, C <: Union{R, Complex{R}}}

    stop(state::AFBA_state) = norm(state.FPR_x, Inf) + norm(state.FPR_y, Inf) <= solver.tol
    disp((it, state)) = @printf(
        "%6d | %7.4e\n",
        it, norm(state.FPR_x, Inf)+norm(state.FPR_y, Inf)
    )

    if solver.gamma1 === nothing || solver.gamma2 === nothing
        gamma1, gamma2 = AFBA_default_stepsizes(
            L, h, solver.theta, solver.mu, betaQ, betaR
        )
    else
        gamma1, gamma2 = solver.gamma1, solver.gamma2
    end

    iter = AFBA_iterable(f, g, h, l, L, x0, y0,
        solver.theta, solver.mu, solver.lambda, gamma1, gamma2
    )
    iter = take(halt(iter, stop), solver.maxit)
    iter = enumerate(iter)
    if solver.verbose iter = tee(sample(iter, solver.freq), disp) end

    num_iters, state_final = loop(iter)

    return state_final.x, state_final.y, num_iters
end

# Outer constructors

"""
    AFBA([gamma1, gamma2, theta, mu, lambda, maxit, tol, verbose, freq])

Instantiate the asymmetric forward-backward-adjoing algorithm (AFBA, see [1])
for solving convex optimization problems of the form

    minimize f(x) + g(x) + (h □ l)(L x),

where `f` is smooth, `g` and `h` are possibly nonsmooth and `l` is strongly
convex. Symbol `□` denotes the infimal convolution, and `L` is a linear mapping.
If `solver = AFBA(args...)`, then the above problem is solved with

    solver(x0, y0; [f, g, h, l, L, betaQ, betaR])

Points `x0` and `y0` are the initial primal and dual iterates, respectively.
If unspecified, functions `f`, `g`, and `h` default to the identically zero
function, `l` defaults to the indicator of the set `{0}`, and `L` defaults to
the identity. Important keyword arguments, in case `f` and `l` are set, are:

* `betaQ`: Lipschitz constant of gradient of `f` (default: zero)
* `betaR`: Lipschitz constant of gradient of the conjugate of `l` (default: zero)

These are used to determine the algorithm default stepsizes, `gamma1` and `gamma2`,
in case they are not directly specified.

Optional keyword arguments are:

* `gamma1`: stepsize corresponding to the primal updates (default: see [1] for each case)
* `gamma2`: stepsize corresponding to the dual updates (default: see [1] for each case)
* `theta`: nonnegative algorithm parameter (default: `1.0`)
* `mu`: algorithm parameter in the range [0,1] (default: `1.0`)
* `tol`: primal-dual termination tolerance (default: `1e-5`)
* `maxit`: maximum number of iterations (default: `10000`)
* `verbose`, verbosity level (default: `1`)
* `verbose_freq`, verbosity frequency for `verbose = 1` (default: `100`)

The iterator implements Algorithm 3 of [1] with constant stepsize (α_n=λ)
for several prominant special cases:
1) θ = 2          ==>   Corresponds to the Vu-Condat Algorithm [2,3].
2) θ = 1, μ=1
3) θ = 0, μ=1
4) θ ∈ [0,∞), μ=0

See [1, Figure 1] for other special cases and relation to other algorithms.

References:

[1] Latafat, Patrinos, "Asymmetric forward–backward–adjoint splitting for
solving monotone inclusions involving three operators", Computational
Optimization and Applications, vol. 68, no. 1, pp. 57-93 (2017).

[2] Condat, "A primal–dual splitting method for convex optimization
involving Lipschitzian, proximable and linear composite terms",
Journal of Optimization Theory and Applications, vol. 158, no. 2,
pp 460-479 (2013).

[3] Vũ, "A splitting algorithm for dual monotone inclusions involving
cocoercive operators", Advances in Computational Mathematics, vol. 38, no. 3,
pp. 667-681 (2013).
"""
AFBA(::Type{R}; kwargs...) where R = AFBA{R}(; kwargs...)
AFBA(; kwargs...) = AFBA(Float64; kwargs...)

"""
    VuCondat([gamma1, gamma2, theta, mu, lambda, maxit, tol, verbose, freq])

Instantiate the Vû-Condat splitting algorithm (see [2, 3])
for solving convex optimization problems of the form

    minimize f(x) + g(x) + (h □ l)(L x),

where `f` is smooth, `g` and `h` are possibly nonsmooth and `l` is strongly
convex. Symbol `□` denotes the infimal convolution, and `L` is a linear mapping.
If `solver = VuCondat(args...)`, then the above problem is solved with

    solver(x0, y0; [f, g, h, l, L, betaQ, betaR])

See documentation of `AFBA` for the list of keyword arguments.

References:

[1] Chambolle, Pock, "A First-Order Primal-Dual Algorithm for Convex Problems
with Applications to Imaging", Journal of Mathematical Imaging and Vision,
vol. 40, no. 1, pp. 120-145 (2011).

[2] Condat, "A primal–dual splitting method for convex optimization
involving Lipschitzian, proximable and linear composite terms",
Journal of Optimization Theory and Applications, vol. 158, no. 2,
pp 460-479 (2013).

[3] Vũ, "A splitting algorithm for dual monotone inclusions involving
cocoercive operators", Advances in Computational Mathematics, vol. 38, no. 3,
pp. 667-681 (2013).
"""
VuCondat(::Type{R}; kwargs...) where R = AFBA{R}(; kwargs..., theta=R(2.0))
VuCondat(; kwargs...) = VuCondat(Float64; kwargs...)
