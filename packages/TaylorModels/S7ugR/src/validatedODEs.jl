# Some methods for validated integration of ODEs

"""
    remainder_taylorstep!(f!, t, x, dx, xI, dxI, δI, δt, params)

Returns a remainder for the integration step for the dependent variables (`x`)
checking that the solution satisfies the criteria for existence and uniqueness.
"""
function remainder_taylorstep!(f!::Function, t::Taylor1{T},
        x::Vector{Taylor1{TaylorN{T}}}, dx::Vector{Taylor1{TaylorN{T}}},
        xI::Vector{Taylor1{Interval{T}}}, dxI::Vector{Taylor1{Interval{T}}},
        δI::IntervalBox{N,T}, δt::Interval{T}, params) where {N,T}

    orderT = get_order(dx[1])
    aux = δt^(orderT+1)
    Δx  = IntervalBox( [  xI[i][orderT+1] * aux for i in eachindex(xI)] )
    Δ0  = IntervalBox( [  dx[i][orderT](δI) * aux / (orderT+1) for i in eachindex(x)] )
    Δdx = IntervalBox( [ dxI[i][orderT+1] * aux for i in eachindex(xI)] )
    Δ = Δ0 + Δdx * δt
    Δxold = Δx

    # Checking existence and uniqueness
    iscontractive(Δ, Δx) && return Δx

    # If the check didn't work, compute new remainders. A new Δx is proposed,
    # and the corresponding Δdx is computed
    xxI  = Array{Taylor1{TaylorN{Interval{T}}}}(undef, N)
    dxxI = Array{Taylor1{TaylorN{Interval{T}}}}(undef, N)
    vv = Array{Interval{T}}(undef, N)
    for its = 1:10
        # Remainder of Picard iteration
        Δ = picard_remainder!(f!, t, x, dx, xxI, dxxI, δI, δt, Δx, Δ0, params)

        # Checking existence and uniqueness
        iscontractive(Δ, Δx) && return Δx
        # iscontractive(Δ, Δx) && return _contract_iteration!(f!, t, x, dx, xxI, dxxI, δI, δt, Δx, Δdx, Δ0, params)

        # Expand Δx in the directions needed
        Δxold = Δx
        if Δ ⊆ Δx
            @inbounds for ind in 1:N
                # Widen the directions where ⊂ does not hold
                vv[ind] = Δx[ind]
                if Δ[ind] == Δx[ind]
                    vv[ind] = widen.(Δ[ind])
                end
            end
            Δx = IntervalBox(vv)
            continue
        end
        Δx = Δ
    end

    # If it didn't work, throw an error
    @format full
    error("""
    Error: it cannot prove existence and unicity of the solution:
        t0 = $(t[0])
        δt = $(δt)
        Δ  = $(Δ)
        Δxo = $(Δxold)
        Δx = $(Δx)
        $(Δ .⊆ Δxold)
    """)
end


"""
    iscontractive(Δ, Δx)

Checks if `Δ .⊂ Δx` is satisfied. If ``Δ ⊆ Δx` is satisfied, it returns
`true` if all cases where `==` holds corresponds to the zero `Interval`.
"""
function iscontractive(Δ::IntervalBox{N,T}, Δx::IntervalBox{N,T}) where{N,T}
    zi = Interval{T}(0, 0)
    @inbounds for ind in 1:N
        Δ[ind] ⊂ Δx[ind] && continue
        Δ[ind] == Δx[ind] == zi && continue
        return false
    end
    return true
end


"""
    picard_remainder!(f!, t, x, dx, xxI, dxxI, δI, δt, Δx, Δ0, params)

Return the remainder of Picard operator
"""
function picard_remainder!(f!::Function, t::Taylor1{T},
    x::Vector{Taylor1{TaylorN{T}}}, dx::Vector{Taylor1{TaylorN{T}}},
    xxI::Vector{Taylor1{TaylorN{Interval{T}}}},
    dxxI::Vector{Taylor1{TaylorN{Interval{T}}}},
    δI::IntervalBox{N,T}, δt::Interval{T},
    Δx::IntervalBox{N,T}, Δ0::IntervalBox{N,T}, params) where {N,T}

    # Extend `x` and `dx` to have interval coefficients
    zI = zero(Interval{T})
    @inbounds for ind in eachindex(x)
        xxI[ind]  = x[ind] + Δx[ind]
        dxxI[ind] = dx[ind] + zI
    end

    # Compute `dxxI` from the equations of motion
    f!(dxxI, xxI, params, t)

    # Picard iteration, considering only the bound of `f` and the last coeff of f
    Δdx = IntervalBox( evaluate.( (dxxI - dx)(δt), δI... ) )
    Δ = Δ0 + Δdx * δt
    return Δ
end


# Picard iterations to contract further Δx, once Δ ⊂ Δx holds
# **Currently not used**
function _contract_iteration!(f!::Function, t::Taylor1{T},
        x::Vector{Taylor1{TaylorN{T}}}, dx::Vector{Taylor1{TaylorN{T}}},
        xxI::Vector{Taylor1{TaylorN{Interval{T}}}}, dxxI::Vector{Taylor1{TaylorN{Interval{T}}}},
        δI::IntervalBox{N,T}, δt::Interval{T},
        Δx::IntervalBox{N,T}, Δdx::IntervalBox{N,T}, Δ0::IntervalBox{N,T}, params) where {N,T}

    # Some abbreviations
    Δ = Δ0 + Δdx * δt
    Δxold = Δx

    # Picard contractions
    for its = 1:10
        # Remainder of Picard iteration
        Δ = picard_remainder!(f!, t, x, dx, xxI, dxxI, δI, δt, Δx, Δ0, params)

        # If contraction doesn't hold, return old bound
        iscontractive(Δ, Δx) || return Δxold

        # Contract estimate
        Δxold = Δx
        Δx = Δ
    end

    return Δxold
end


"""
    absorb_remainder(a::TaylorModelN)

Returns a TaylorModelN, equivalent to `a`, such that the remainder
is mostly absorbed in the constant and linear coefficients. The linear shift assumes
that `a` is normalized to the `IntervalBox(-1..1, Val(N))`.

Ref: Xin Chen, Erika Abraham, and Sriram Sankaranarayanan,
"Taylor Model Flowpipe Construction for Non-linear Hybrid
Systems", in Real Time Systems Symposium (RTSS), pp. 183-192 (2012),
IEEE Press.
"""
function absorb_remainder(a::TaylorModelN{N,T,T}) where {N,T}
    Δ = remainder(a)
    orderQ = get_order(a)
    δ = IntervalBox(Interval{T}(-1,1), Val(N))
    aux = diam(Δ)/(2N)
    rem = Interval{T}(0, 0)

    # Linear shift
    lin_shift = mid(Δ) + sum((aux*TaylorN(i, order=orderQ) for i in 1:N))
    bpol = a.pol + lin_shift

    # Compute the new remainder
    aI = a(δ)
    bI = bpol(δ)

    if bI ⊆ aI
        rem = Interval(aI.lo-bI.lo, aI.hi-bI.hi)
    elseif aI ⊆ bI
        rem = Interval(bI.lo-aI.lo, bI.hi-aI.hi)
    else
        r_lo = aI.lo-bI.lo
        r_hi = aI.hi-bI.hi
        if r_lo > 0
            rem = Interval(-r_lo, r_hi)
        else
            rem = Interval( r_lo, -r_hi)
        end
    end

    return TaylorModelN(bpol, rem, a.x0, a.dom)
end


"""
    shrink_wrapping!(xTMN::TaylorModelN)

Returns a modified inplace `xTMN`, which has absorbed the remainder
by the modified shrink-wrapping method of Florian Bünger.

Ref: Florian B\"unger, Shrink wrapping for Taylor models revisited,
Numer Algor 78:1001–1017 (2018), https://doi.org/10.1007/s11075-017-0410-1
"""
function shrink_wrapping!(xTMN::Vector{TaylorModelN{N,T,T}}) where {N,T}
    # Original domain of TaylorModelN
    B = IntervalBox(Interval{T}(-1,1), Val(N))
    zI = zero(Interval{T})

    # Vector of independent TaylorN variables
    order = get_order(xTMN[1])
    X = [TaylorN(T, i, order=order) for i in 1:N]

    # Remainder of original TaylorModelN and componentwise mag
    rem = remainder.(xTMN)
    r = mag.(rem)
    qB = r .* B

    # Shift to remove constant term
    xTN0 = constant_term.(xTMN)
    xTNcent = polynomial.(xTMN) .- xTN0

    # Jacobian (at zero) and its inverse
    jac = TaylorSeries.jacobian(xTNcent)
    ## If conditional number is too large, use absorb_remainder
    if cond(jac) > 1.0e4
        for i in eachindex(xTMN)
            # If remainder is still too big, do it again
            j = 0
            while (j < 10) && (mag(rem[i]) > 1.0e-12)
                j += 1
                xTMN[i] = absorb_remainder(xTMN[i])
                rem[i] = remainder(xTMN[i])
            end
        end
        return xTMN
    end
    invjac = inv(jac)

    # Componentwise bound
    r̃ = mag.(invjac * qB) # qB <-- r .* B
    qB´ = r̃ .* B
    @assert invjac * qB ⊆ qB´

    # Nonlinear part (linear part is close to identity)
    g = invjac*xTNcent .- X
    # g = invjac*(xTNcent .- linear_polynomial.(xTNcent))
    # ... and its jacobian matrix (full dependence!)
    jacmatrix_g = TaylorSeries.jacobian(g, X)

    # Step 7 of Bünger algorithm: obtain an estimate of `q`
    # Some constants/parameters
    q_tol = 1.0e-12
    q = 1.0 .+ r̃
    ff = 65/64
    q_max = ff .* q
    zs = zero(q)
    s = similar(q)
    q_old = similar(q)
    q_1 = similar(q)
    jaq_q1 = jacmatrix_g * r̃

    iter_max = 100
    improve = true
    iter = 0
    while improve && iter < iter_max
        qB .= q .* B
        s .= zs
        q_old .= q
        q_1 .= q_old .- 1.0
        mul!(jaq_q1, jacmatrix_g, q_1)
        @inbounds for i in eachindex(xTMN)
            s[i] = mag( jaq_q1[i](qB) )
            q[i] = 1.0 + r̃[i] + s[i]
            # If q is too large, return xTMN unchanged
            q[i] > q_max[i] && return xTMN
        end
        improve = any( ((q .- q_old)./q) .> q_tol )
        iter += 1
    end
    # (improve || q == one.(q)) && return xTMN

    # Compute final q and rescale X
    @. q = 1.0 + r̃ + ff * s
    @. X = q * X

    # Postverify and define Taylor models to be returned
    @inbounds for i in eachindex(xTMN)
        pol = polynomial(xTMN[i])
        ppol = fp_rpa(TaylorModelN(pol(X), zI, xTMN[i].x0, xTMN[i].dom ))
        if xTMN[i](B) ⊆ polynomial(ppol)(B) # assumes zero remainder
            xTMN[i] = TaylorModelN(pol, zI, xTMN[i].x0, xTMN[i].dom )
        else
            xTMN[i] = fp_rpa(TaylorModelN(xTMN[i](X), zI, xTMN[i].x0, xTMN[i].dom ))
        end
    end

    return xTMN
end


"""
    validated-step!
"""
function validated_step!(f!, t::Taylor1{T},
        x::Vector{Taylor1{TaylorN{T}}}, dx::Vector{Taylor1{TaylorN{T}}}, xaux::Vector{Taylor1{TaylorN{T}}},
        tI::Taylor1{T},
        xI::Vector{Taylor1{Interval{T}}}, dxI::Vector{Taylor1{Interval{T}}}, xauxI::Vector{Taylor1{Interval{T}}},
        t0::T, tmax::T, xTMN::Vector{TaylorModelN{N,T,T}},
        xv::Vector{IntervalBox{N,T}},
        rem::Vector{Interval{T}}, δq_norm::IntervalBox{N,T},
        q0::IntervalBox{N,T}, q0box::IntervalBox{N,T}, nsteps::Int,
        orderT::Int, abstol::T, params, parse_eqs::Bool,
        check_property::Function=(t, x)->true) where {N,T}

    # One step integration (non-validated)
    # TaylorIntegration.__jetcoeffs!(Val(parse_eqs), f!, t, x, dx, xaux, params)
    # δt = TaylorIntegration.stepsize(x, abstol)
    δt = TaylorIntegration.taylorstep!(f!, t, x, dx, xaux,
        t0, tmax, orderT, abstol, params, parse_eqs)
    # One step integration for the initial box
    # TaylorIntegration.__jetcoeffs!(Val(parse_eqs), f!, tI, xI, dxI, xauxI, params)
    # δtI = TaylorIntegration.stepsize(xI, abstol)
    δtI = TaylorIntegration.taylorstep!(f!, tI, xI, dxI, xauxI,
        t0, tmax, orderT+1, abstol, params, parse_eqs)

    # # Step size
    # δt = min(δt, tmax-t0, inf(δtI))
    δtI = Interval{T}(0.0, δt)

    # This updates the `dx[:][orderT]` and `dxI[:][orderT+1]`, which are currently zero
    f!(dx, x, params, t)
    f!(dxI, xI, params, tI)

    # Test if `check_property` is satisfied; if not, half the integration time.
    # If after 25 checks `check_property` is not satisfied, throw an error.
    nsteps += 1
    issatisfied = false
    rem_old = copy(rem)
    for nchecks = 1:25
        # Validate the solution: remainder consistent with Schauder thm
        Δ = remainder_taylorstep!(f!, t, x, dx, xI, dxI, δq_norm, δtI, params)
        rem .= rem_old .+ Δ

        # Create TaylorModelN to store remainders and evaluation
        @inbounds begin
            for i in eachindex(x)
                xTMN[i] = fp_rpa( TaylorModelN(x[i](0..δt), rem[i], q0, q0box) )

                # If remainder is still too big, do it again
                j = 0
                while (j < 10) && (mag(rem[i]) > 1.0e-10)
                    j += 1
                    xTMN[i] = absorb_remainder(xTMN[i])
                    rem[i] = remainder(xTMN[i])
                end
            end
            xv[nsteps] = evaluate(xTMN, δq_norm) # IntervalBox

            if !check_property(t0+δt, xv[nsteps])
                δt = δt/2
                continue
            end
        end # @inbounds

        issatisfied = true
        break
    end

    if !issatisfied
        error("""
            `check_property` is not satisfied:
            $t0 $nsteps $δt
            $(xv[nsteps])
            $(check_property(t0+δt, xv[nsteps]))""")
    end

    return δt
end


function validated_integ(f!, qq0::AbstractArray{T,1}, δq0::IntervalBox{N,T},
        t0::T, tmax::T, orderQ::Int, orderT::Int, abstol::T, params=nothing;
        maxsteps::Int=500, parse_eqs::Bool=true,
        check_property::Function=(t, x)->true) where {N, T<:Real}

    # Set proper parameters for jet transport
    @assert N == get_numvars()
    dof = N

    # Some variables
    zI = zero(Interval{T})
    q0 = IntervalBox(qq0)
    t   = t0 + Taylor1(orderT)
    tI  = t0 + Taylor1(orderT+1)
    δq_norm = IntervalBox(Interval{T}(-1, 1), Val(N))
    q0box = q0 .+ δq_norm

    # Allocation of vectors
    # Output
    tv    = Array{T}(undef, maxsteps+1)
    xv    = Array{IntervalBox{N,T}}(undef, maxsteps+1)
    xTM1v = Array{TaylorModel1{TaylorN{T},T}}(undef, dof, maxsteps+1)
    # Internals: jet transport integration
    x     = Array{Taylor1{TaylorN{T}}}(undef, dof)
    dx    = Array{Taylor1{TaylorN{T}}}(undef, dof)
    xaux  = Array{Taylor1{TaylorN{T}}}(undef, dof)
    xTMN  = Array{TaylorModelN{N,T,T}}(undef, dof)
    # Internals: Taylor1{Interval{T}} integration
    xI    = Array{Taylor1{Interval{T}}}(undef, dof)
    dxI   = Array{Taylor1{Interval{T}}}(undef, dof)
    xauxI = Array{Taylor1{Interval{T}}}(undef, dof)

    # Set initial conditions
    rem = Array{Interval{T}}(undef, dof)
    @inbounds for i in eachindex(x)
        qaux = normalize_taylor(qq0[i] + TaylorN(i, order=orderQ), δq0, true)
        x[i] = Taylor1( qaux, orderT)
        dx[i] = x[i]
        xTMN[i] = TaylorModelN(qaux, zI, q0, q0box)
        #
        xI[i] = Taylor1( q0[i]+δq0[i], orderT+1 )
        dxI[i] = xI[i]
        rem[i] = zI
        #
        xTM1v[i, 1] = TaylorModel1(deepcopy(x[i]), zI, zI, zI)
    end

    # Output vectors
    @inbounds tv[1] = t0
    @inbounds xv[1] = evaluate(xTMN, δq_norm)

    # Determine if specialized jetcoeffs! method exists (built by @taylorize)
    parse_eqs = parse_eqs && (length(methods(TaylorIntegration.jetcoeffs!)) > 2)
    if parse_eqs
        try
            TaylorIntegration.jetcoeffs!(Val(f!), t, x, dx, params)
        catch
            parse_eqs = false
        end
    end

    # Integration
    nsteps = 1
    while t0 < tmax

        # Validated step of the integration
        δt = validated_step!(f!, t, x, dx, xaux, tI, xI, dxI, xauxI,
            t0, tmax, xTMN, xv, rem, δq_norm, q0, q0box,
            nsteps, orderT, abstol, params, parse_eqs, check_property)

        # New initial conditions and time
        nsteps += 1
        t0 += δt
        @inbounds t[0] = t0
        @inbounds tI[0] = t0
        @inbounds tv[nsteps] = t0
        @inbounds for i in eachindex(x)
            xTM1v[i, nsteps] = TaylorModel1(deepcopy(x[i]), rem[i], zI, Interval{T}(0, δt))
            aux = x[i](δt)
            x[i]  = Taylor1( aux, orderT )
            dx[i] = Taylor1( zero(aux), orderT )
            auxI = xTMN[i](δq_norm)
            xI[i] = Taylor1( auxI, orderT+1 )
            dxI[i] = xI[i]
        end

        if nsteps > maxsteps
            @info("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end

    end

    return view(tv,1:nsteps), view(xv,1:nsteps), view(xTM1v, :, 1:nsteps)
end
