# An implementation of the Lanczos version of the conjugate gradient method
# for a family of shifted systems of the form (A + αI) x = b.
#
# The implementation follows
# A. Frommer and P. Maass, Fast CG-Based Methods for Tikhonov-Phillips
# Regularization, SIAM Journal on Scientific Computing, 20(5),
# pp. 1831-1850, 1999.
#
# Dominique Orban, <dominique.orban@gerad.ca>
# Princeton, NJ, March 2015.

export cg_lanczos, cg_lanczos_shift_seq


"""The Lanczos version of the conjugate gradient method to solve the
symmetric linear system

  Ax = b

The method does _not_ abort if A is not definite.

A preconditioner M may be provided in the form of a linear operator and is
assumed to be symmetric and positive definite.
"""
function cg_lanczos(A :: AbstractLinearOperator, b :: AbstractVector{T};
                    M :: AbstractLinearOperator=opEye(),
                    atol :: Float64=1.0e-8, rtol :: Float64=1.0e-6, itmax :: Int=0,
                    check_curvature :: Bool=false, verbose :: Bool=false) where T <: Number

  n = size(b, 1);
  (size(A, 1) == n & size(A, 2) == n) || error("Inconsistent problem size");
  verbose && @printf("CG Lanczos: system of %d equations in %d variables\n", n, n);

  # Tests M == Iₙ
  MisI = isa(M, opEye)

  # Initial state.
  x = zeros(T, n)           # x₀
  Mv = copy(b)              # Mv₁ ← b
  v = M * Mv                # v₁ = M⁻¹ * Mv₁
  β = sqrt(@kdot(n, v, Mv)) # β₁ = v₁ᵀ M v₁
  β == 0 && return x, LanczosStats(true, [0.0], false, 0.0, 0.0, "x = 0 is a zero-residual solution")
  p = copy(v)

  # Initialize Lanczos process.
  # β₁Mv₁ = b
  @kscal!(n, 1.0/β, v)          # v₁  ←  v₁ / β₁
  MisI || @kscal!(n, 1.0/β, Mv) # Mv₁ ← Mv₁ / β₁
  Mv_prev = copy(Mv)

  iter = 0;
  itmax == 0 && (itmax = 2 * n);

  # Initialize some constants used in recursions below.
  σ = β;
  ω = 0;
  γ = 1;
  Anorm2 = 0.0;
  β_prev = 0.0;

  # Define stopping tolerance.
  rNorm = σ;
  rNorms = [rNorm;];
  ε = atol + rtol * rNorm;
  verbose && @printf("%5d  %8.1e\n", iter, rNorm);

  indefinite = false;
  solved = rNorm <= ε;
  tired = iter >= itmax;
  status = "unknown";

  # Main loop.
  while ! (solved || tired || (check_curvature & indefinite))
    # Form next Lanczos vector.
    # βₖ₊₁Mvₖ₊₁ = Avₖ - δₖMvₖ - βₖMvₖ₋₁
    Mv_next = A * v          # Mvₖ₊₁ ← Avₖ
    δ = @kdot(n, v, Mv_next) # δₖ = vₖᵀ A vₖ

    # Check curvature. Exit fast if requested.
    # It is possible to show that σₖ² (δₖ - ωₖ₋₁ / γₖ₋₁) = pₖᵀ A pₖ.
    γ = 1 / (δ - ω / γ)      # γₖ = δₖ - ωₖ₋₁ / γₖ₋₁
    indefinite |= (γ <= 0.0);
    (check_curvature & indefinite) && continue;

    @kaxpy!(n, -δ, Mv, Mv_next)        # Mvₖ₊₁ ← Mvₖ₊₁ - δₖMvₖ
    if iter > 0
      @kaxpy!(n, -β, Mv_prev, Mv_next) # Mvₖ₊₁ ← Mvₖ₊₁ - βₖMvₖ₋₁
      @. Mv_prev = Mv                  # Mvₖ₋₁ ← Mvₖ
    end
    @. Mv = Mv_next                    # Mvₖ ← Mvₖ₊₁
    v = M * Mv                         # vₖ₊₁ = M⁻¹ * Mvₖ₊₁
    β = sqrt(@kdot(n, v, Mv))          # βₖ₊₁ = vₖ₊₁ᵀ M vₖ₊₁
    @kscal!(n, 1.0/β, v)               # vₖ₊₁  ←  vₖ₊₁ / βₖ₊₁
    MisI || @kscal!(n, 1.0/β, Mv)      # Mvₖ₊₁ ← Mvₖ₊₁ / βₖ₊₁
    Anorm2 += β_prev^2 + β^2 + δ^2     # Use ‖Tₖ₊₁‖₂ as increasing approximation of ‖A‖₂.
    β_prev = β;

    # Compute next CG iterate.
    @kaxpy!(n, γ, p, x)     # xₖ₊₁ = xₖ + γₖ * pₖ
    ω = β * γ 
    σ = -ω * σ              # σₖ₊₁ = - βₖ₊₁ * γₖ * σₖ
    ω = ω * ω               # ωₖ = (βₖ₊₁ * γₖ)²
    @kaxpby!(n, σ, v, ω, p) # pₖ₊₁ = σₖ₊₁ * vₖ₊₁ + ωₖ * pₖ
    rNorm = abs(σ)          # ‖rₖ₊₁‖_M = |σₖ₊₁| because rₖ₊₁ = σₖ₊₁ * vₖ₊₁ and ‖vₖ₊₁‖_M = 1
    push!(rNorms, rNorm);
    iter = iter + 1;
    verbose && @printf("%5d  %8.1e\n", iter, rNorm);
    solved = rNorm <= ε;
    tired = iter >= itmax;
  end

  status = tired ? "maximum number of iterations exceeded" : (check_curvature & indefinite) ? "negative curvature" : "solution good enough given atol and rtol"
  stats = LanczosStats(solved, rNorms, indefinite, sqrt(Anorm2), 0.0, status);  # TODO: Estimate Acond.
  return (x, stats);
end


"""The Lanczos version of the conjugate gradient method to solve a family
of shifted systems

  (A + αI) x = b  (α = α₁, α₂, ...)

The method does _not_ abort if A + αI is not definite.
"""
function cg_lanczos_shift_seq(A :: AbstractLinearOperator, b :: AbstractVector{Tb}, shifts :: AbstractVector{Ts};
                              atol :: Float64=1.0e-8, rtol :: Float64=1.0e-6, itmax :: Int=0,
                              check_curvature :: Bool=false, verbose :: Bool=false) where {Tb, Ts <: Number}

  n = size(b, 1);
  (size(A, 1) == n & size(A, 2) == n) || error("Inconsistent problem size");

  nshifts = size(shifts, 1);
  verbose && @printf("CG Lanczos: system of %d equations in %d variables with %d shifts\n", n, n, nshifts);

  # Initial state.
  ## Distribute x similarly to shifts.
  x = [zeros(Tb, n) for i = 1 : nshifts]
  β = @knrm2(n, b)
  β == 0 && return x, LanczosStats(true, [0.0], false, 0.0, 0.0, "x = 0 is a zero-residual solution")
  v = b / β;
  v_prev = copy(v);

  # Initialize each p to b.
  p = [copy(b) for i = 1 : nshifts]

  # Initialize some constants used in recursions below.
  σ = β * ones(nshifts);
  δhat = zeros(nshifts);
  ω = zeros(Tb, nshifts);
  γ = ones(Tb, nshifts);

  # Define stopping tolerance.
  rNorms = β * ones(Tb, nshifts);
  rNorms_history = [rNorms;];
  ε = atol + rtol * β;

  # Keep track of shifted systems that have converged.
  converged = rNorms .<= ε;
  iter = 0;
  itmax == 0 && (itmax = 2 * n);

  # Keep track of shifted systems with negative curvature if required.
  indefinite = falses(nshifts);

  # Build format strings for printing.
  if verbose
    fmt = "%5d" * repeat("  %8.1e", nshifts) * "\n";
    # precompile printf for our particular format
    local_printf(data...) = Core.eval(Main, :(@printf($fmt, $(data)...)))
    local_printf(iter, rNorms...)
  end

  solved = all(converged);
  tired = iter >= itmax;
  status = "unknown";

  # Main loop.
  while ! (solved || tired)
    # Form next Lanczos vector.
    v_next = A * v;
    δ = @kdot(n, v, v_next)
    @kaxpy!(n, -δ, v, v_next)  # Faster than v_next = Av - δ * v;
    if iter > 0
      @kaxpy!(n, -β, v_prev, v_next)  # Faster than v_next = v_next - β * v_prev;
      @. v_prev = v;
    end
    β = @knrm2(n, v_next)
    @. v = v_next / β;

    # Check curvature: v'(A + sᵢI)v = v'Av + sᵢ ‖v‖² = δ + sᵢ because ‖v‖ = 1.
    # It is possible to show that σⱼ² (δⱼ + sᵢ - ωⱼ₋₁ / γⱼ₋₁) = pⱼᵀ (A + sᵢ I) pⱼ.
    for i = 1 : nshifts
      δhat[i] = δ + shifts[i]
      γ[i] = 1 ./ (δhat[i] - ω[i] ./ γ[i])
    end
    indefinite .|= (γ .<= 0.0);

    # Compute next CG iterate for each shifted system that has not yet converged.
    # Stop iterating on indefinite problems if requested.
    not_cv = check_curvature ? findall(.! (converged .| indefinite)) : findall(.! converged);

    for i in not_cv
      @kaxpy!(n, γ[i], p[i], x[i])
      ω[i] = β * γ[i];
      σ[i] *= -ω[i];
      ω[i] *= ω[i];
      @kaxpby!(n, σ[i], v, ω[i], p[i])

      # Update list of systems that have converged.
      rNorms[i] = abs(σ[i]);
      converged[i] = rNorms[i] <= ε;
    end

    length(not_cv) > 0 && append!(rNorms_history, rNorms);

    # Is there a better way than to update this array twice per iteration?
    not_cv = check_curvature ? findall(.! (converged .| indefinite)) : findall(.! converged);
    iter = iter + 1;
    verbose && local_printf(iter, rNorms...)

    solved = length(not_cv) == 0;
    tired = iter >= itmax;
  end

  status = tired ? "maximum number of iterations exceeded" : "solution good enough given atol and rtol"
  stats = LanczosStats(solved, permutedims(reshape(rNorms_history, nshifts, round(Int, sum(size(rNorms_history))/nshifts))), indefinite, 0.0, 0.0, status);  # TODO: Estimate Anorm and Acond.
  return (x, stats);
end
