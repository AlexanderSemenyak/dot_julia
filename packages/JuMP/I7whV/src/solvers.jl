#  Copyright 2017, Iain Dunning, Joey Huchette, Miles Lubin, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
# JuMP
# An algebraic modeling language for Julia
# See http://github.com/JuliaOpt/JuMP.jl
#############################################################################
# src/solvers.jl
# Handles conversion of the JuMP Model into a format that can be passed
# through the MathProgBase interface to solvers, and ongoing updating of
# that representation if supported by the solver.
#############################################################################

# Analyze a JuMP Model to determine its traits, and thus what solvers can
# be used to solve the problem
mutable struct ProblemTraits
    int::Bool  # has integer variables
    lin::Bool  # has only linear objectives and constraints
    qp ::Bool  # has a quadratic objective function
    qc ::Bool  # has a quadratic constraint
    nlp::Bool  # has general nonlinear objective or constraints
    soc::Bool  # has a second-order cone constraint
    sdp::Bool  # has an SDP constraint (or SDP variable bounds)
    sos::Bool  # has an SOS constraint
    conic::Bool  # has an SDP or SOC constraint
end
function ProblemTraits(m::Model; relaxation=false)
    int = !relaxation && any(c-> !(c == :Cont || c == :Fixed), m.colCat)
    qp = !isempty(m.obj.qvars1)
    qc = !isempty(m.quadconstr)
    nlp = m.nlpdata !== nothing
    soc = !isempty(m.socconstr)
    # will need to change this when we add support for arbitrary variable cones
    sdp = !isempty(m.sdpconstr) || !isempty(m.varCones)
    sos = !isempty(m.sosconstr)
    ProblemTraits(int, !(qp|qc|nlp|soc|sdp|sos), qp, qc, nlp, soc, sdp, sos, soc|sdp)
end

const suggestedsolvers = Dict("LP" => [(:Clp,:ClpSolver),
                                       (:GLPKMathProgInterface,:GLPKSolverLP),
                                       (:Gurobi,:GurobiSolver),
                                       (:CPLEX,:CplexSolver),
                                       (:Mosek,:MosekSolver),
                                       (:Xpress,:XpressSolver)],
                              "MIP" => [(:Cbc,:CbcSolver),
                                        (:GLPKMathProgInterface,:GLPKSolverMIP),
                                        (:Gurobi,:GurobiSolver),
                                        (:CPLEX,:CplexSolver),
                                        (:Mosek,:MosekSolver),
                                        (:Xpress,:XpressSolver)],
                              "QP" => [(:Gurobi,:GurobiSolver),
                                       (:CPLEX,:CplexSolver),
                                       (:Mosek,:MosekSolver),
                                       (:Ipopt,:IpoptSolver),
                                       (:Xpress,:XpressSolver)],
                              "SDP" => [(:Mosek,:MosekSolver),
                                       (:SCS,:SCSSolver)],
                              "NLP" => [(:Ipopt,:IpoptSolver),
                                        (:KNITRO,:KnitroSolver),
                                        (:Mosek,:MosekSolver)],
                              "Conic" => [(:ECOS,:ECOSSolver),
                                         (:SCS,:SCSSolver),
                                         (:Mosek,:MosekSolver)])

function no_solver_error(traits::ProblemTraits)

    # This is pretty coarse and misses out on MIConic, MIQP, etc.
    if traits.nlp
        class = "NLP"
    elseif traits.int || traits.sos
        class = "MIP"
    elseif traits.sdp
        class = "SDP"
    elseif traits.conic
        class = "Conic"
    elseif traits.qp || traits.qc
        class = "QP"
    else
        class = "LP"
    end
    solverlist = join([string(p) for (p,s) in suggestedsolvers[class]], ", ", ", and ")
    error("No solver was provided. JuMP has classified this model as $class. Julia packages which provide solvers for this class of problems include $solverlist. The solver must be specified by using either the \"solver=\" keyword argument to \"Model()\" or the \"setsolver()\" method.")
end

function fillConicRedCosts(m::Model)
    bndidx = 0
    numlinconstr = length(m.linconstr)
    vardual = MathProgBase.getvardual(m.internalModel)
    offdiagvars = offdiagsdpvars(m)
    vardual[offdiagvars] /= sqrt(2)
    for i in 1:m.numCols
        lower = false
        upper = false
        lb, ub = m.colLower[i], m.colUpper[i]

        if lb != -Inf && lb != 0.0
            lower = true
            bndidx += 1
        end
        if ub != Inf && ub != 0.0
            upper = true
            bndidx += 1
        end

        if lower && !upper
            m.redCosts[i] = m.conicconstrDuals[numlinconstr + bndidx]
        elseif !lower && upper
            m.redCosts[i] = m.conicconstrDuals[numlinconstr + bndidx]
        elseif lower && upper
            m.redCosts[i] = m.conicconstrDuals[numlinconstr + bndidx]+m.conicconstrDuals[numlinconstr + bndidx-1]
        end
        m.redCosts[i] += vardual[i]
    end
end

function fillConicDuals(m::Model)

    numLinRows, numCols = length(m.linconstr), m.numCols
    numBndRows = getNumBndRows(m)
    numSOCRows = getNumSOCRows(m)
    numSDPRows = getNumSDPRows(m)
    numSymRows = getNumSymRows(m)
    numRows = numLinRows+numBndRows+numSOCRows+numSDPRows+numSymRows

    m.conicconstrDuals = try
        MathProgBase.getdual(m.internalModel)
    catch
        fill(NaN, numRows)
    end

    if numRows == 0 || isfinite(m.conicconstrDuals[1]) # NaN could mean unavailable
        if m.objSense == :Min
            rmul!(m.conicconstrDuals, -1)
        end
        m.linconstrDuals = m.conicconstrDuals[1:numLinRows]
        m.redCosts = zeros(numCols)
        fillConicRedCosts(m)
    end

end

function solve(m::Model; suppress_warnings=false,
                ignore_solve_hook=(m.solvehook===nothing),
                relaxation=false,
                kwargs...)
    # If the user or an extension has provided a solve hook, call
    # that instead of solving the model ourselves
    if !ignore_solve_hook
        return m.solvehook(m; suppress_warnings=suppress_warnings, kwargs...)::Symbol
    end

    isempty(kwargs) || error("Unrecognized keyword arguments: $(join([k[1] for k in kwargs], ", "))")

    # Clear warning counters
    m.map_counter = 0
    m.operator_counter = 0

    # Remember if the solver was initially unset so we can restore
    # it to be unset later
    unset = m.solver == UnsetSolver()

    # Analyze the problems traits to determine what solvers we can use
    traits = ProblemTraits(m, relaxation=relaxation)

    # Build the MathProgBase model from the JuMP model
    build(m, traits=traits, suppress_warnings=suppress_warnings, relaxation=relaxation)

    # If the model is a general nonlinear, use different logic in
    # nlp.jl to solve the problem
    traits.nlp && return solvenlp(m, traits, suppress_warnings=suppress_warnings)

    # Solve the problem
    MathProgBase.optimize!(m.internalModel)
    stat::Symbol = MathProgBase.status(m.internalModel)

    # Extract solution from the solver
    numRows, numCols = length(m.linconstr), m.numCols
    m.objBound = NaN
    m.objVal = NaN
    m.colVal = fill(NaN, numCols)
    m.linconstrDuals = Array{Float64}(undef, 0)

    discrete = !relaxation && (traits.int || traits.sos)
    if stat == :Optimal
        # If we think dual information might be available, try to get it
        # If not, return an array of the correct length
        if discrete
            m.redCosts = fill(NaN, numCols)
            m.linconstrDuals = fill(NaN, numRows)
        else
            if !traits.conic
                m.redCosts = try
                    MathProgBase.getreducedcosts(m.internalModel)[1:numCols]
                catch
                    fill(NaN, numCols)
                end

                m.linconstrDuals = try
                    MathProgBase.getconstrduals(m.internalModel)[1:numRows]
                catch
                    fill(NaN, numRows)
                end
            elseif !traits.qp && !traits.qc
                fillConicDuals(m)
            end
        end
    else
        # Problem was not solved to optimality, attempt to extract useful
        # information anyway
        suppress_warnings || Compat.@warn("Not solved to optimality, status: $stat")
        # Some solvers provide infeasibility rays (dual) or unbounded
        # rays (primal) for linear problems. Store these as the solution
        # if the exist.
        if traits.lin
            if stat == :Infeasible
                m.linconstrDuals = try
                    infray = MathProgBase.getinfeasibilityray(m.internalModel)
                    @assert length(infray) == numRows
                    infray
                catch
                    suppress_warnings || Compat.@warn("Infeasibility ray (Farkas proof) not available")
                    fill(NaN, numRows)
                end
            elseif stat == :Unbounded
                m.colVal = try
                    unbdray = MathProgBase.getunboundedray(m.internalModel)
                    @assert length(unbdray) == numCols
                    unbdray
                catch
                    suppress_warnings || Compat.@warn("Unbounded ray not available")
                    fill(NaN, numCols)
                end
            end
        end
        # conic duals (currently, SOC and SDP only)
        if !discrete && traits.conic && !traits.qp && !traits.qc
            if stat == :Infeasible
                fillConicDuals(m)
            end
        end
    end

    # If the problem was solved, or if it terminated prematurely, try
    # to extract a solution anyway. This commonly occurs when a time
    # limit or tolerance is set (:UserLimit)
    if !(stat == :Infeasible || stat == :Unbounded)
        try
            # Do a separate try since getobjval could work while getobjbound does not and vice versa
            objBound = MathProgBase.getobjbound(m.internalModel) + m.obj.aff.constant
            m.objBound = objBound
        catch
            nothing
        end
        try
            objVal = MathProgBase.getobjval(m.internalModel) + m.obj.aff.constant
            colVal = MathProgBase.getsolution(m.internalModel)[1:numCols]
            # Rescale off-diagonal terms of SDP variables
            if traits.sdp
                offdiagvars = offdiagsdpvars(m)
                colVal[offdiagvars] /= sqrt(2)
            end
            # Don't corrupt the answers if one of the above two calls fails
            m.objVal = objVal
            m.colVal = colVal
        catch
            nothing
        end
    end

    # The MathProgBase interface defines a conic problem to always be a
    # minimization problem, so we need to flip the objective before reporting it
    # to the user. We also need to account for the objective constant which was
    # added above by subtracting it prior to the flip and then re-adding it.
    if traits.conic && m.objSense == :Max
        m.objBound = -1 * (m.objBound - m.obj.aff.constant) + m.obj.aff.constant
        m.objVal = -1 * (m.objVal - m.obj.aff.constant) + m.obj.aff.constant
    end

    # If the solver was initially not set, we will restore this status
    # and drop the internal MPB model. This is important for the case
    # where the solver used changes between solves because the user
    # has changed the problem class (e.g. LP to MILP)
    if unset
        m.solver = UnsetSolver()
        if traits.int
            m.internalModelLoaded = false
        end
    end

    # Return the solve status
    stat
end

# Converts the JuMP Model into a MathProgBase model based on the
# traits of the model
function build(m::Model; suppress_warnings=false, relaxation=false, traits=ProblemTraits(m,relaxation=relaxation))
    if isa(m.solver, UnsetSolver)
        no_solver_error(traits)
    end

    # If the model is nonlinear, use different logic in nlp.jl
    # to build the problem
    traits.nlp && return _buildInternalModel_nlp(m, traits)

    if traits.conic
        # If there are semicontinuous/semi-integer variables, we will have to
        # adjust the b vector below to construct a valid relaxation. This seems
        # like a pretty marginal case, so let's punt on it for now.
        if relaxation && any(x -> (x == :SemiCont || x == :SemiInt), m.colCat)
            error("Relaxations of conic problem with semi-integer/semicontinuous variables are not currently supported.")
        end

        traits.qp && error("JuMP does not support quadratic objectives for conic problems")
        traits.qc && error("JuMP does not support mixing quadratic and conic constraints")

        # Obtain a fresh MPB model for the solver
        # If the problem is conic, we rebuild the problem from
        # scratch every time
        m.internalModel = MathProgBase.ConicModel(m.solver)

        # Build up the objective, LHS, RHS and cones from the JuMP Model...
        f, A, b, var_cones, con_cones = conicdata(m)
        # ... and pass to the solver
        MathProgBase.loadproblem!(m.internalModel, f, A, b, con_cones, var_cones)
    else
        # Extract objective coefficients and linear constraint bounds
        f = prepAffObjective(m)
        rowlb, rowub = prepConstrBounds(m)
        # If we already have an MPB model for the solver...
        if m.internalModelLoaded
            # ... and if the solver supports updating bounds/objective
            if applicable(MathProgBase.setvarLB!, m.internalModel, m.colLower) &&
               applicable(MathProgBase.setvarUB!, m.internalModel, m.colUpper) &&
               applicable(MathProgBase.setconstrLB!, m.internalModel, rowlb) &&
               applicable(MathProgBase.setconstrUB!, m.internalModel, rowub) &&
               applicable(MathProgBase.setobj!, m.internalModel, f) &&
               applicable(MathProgBase.setsense!, m.internalModel, m.objSense)
                MathProgBase.setvarLB!(m.internalModel, copy(m.colLower))
                MathProgBase.setvarUB!(m.internalModel, copy(m.colUpper))
                MathProgBase.setconstrLB!(m.internalModel, rowlb)
                MathProgBase.setconstrUB!(m.internalModel, rowub)
                MathProgBase.setobj!(m.internalModel, f)
                MathProgBase.setsense!(m.internalModel, m.objSense)
            else
                # The solver doesn't support changing bounds/objective
                # We need to build the model from scratch
                if !suppress_warnings
                    warn_once("Solver does not appear to support hot-starts. Model will be built from scratch.")
                end
                m.internalModelLoaded = false
            end
        end
        # If we don't already have a MPB model
        if !m.internalModelLoaded
            # Obtain a fresh MPB model for the solver
            m.internalModel = MathProgBase.LinearQuadraticModel(m.solver)
            # Construct a LHS matrix from the linear constraints
            A = prepConstrMatrix(m)

            # Load the problem data into the model...
            collb = copy(m.colLower)
            colub = copy(m.colUpper)
            if relaxation
                for i in 1:m.numCols
                    if m.colCat[i] in (:SemiCont,:SemiInt)
                        collb[i] = min(0.0, collb[i])
                        colub[i] = max(0.0, colub[i])
                    end
                end
            end
            MathProgBase.loadproblem!(m.internalModel, A, collb, colub, f, rowlb, rowub, m.objSense)
            # ... and add quadratic and SOS constraints separately
            addQuadratics(m)
            if !relaxation
                addSOS(m)
            end
        end

    end
    # Update solver callbacks, if any
    if !relaxation
        registercallbacks(m)
    end

    # Update the type of each variable
    if applicable(MathProgBase.setvartype!, m.internalModel, Symbol[])
        if relaxation
            MathProgBase.setvartype!(m.internalModel, fill(:Cont, m.numCols))
        else
            colCats = vartypes_without_fixed(m)
            MathProgBase.setvartype!(m.internalModel, colCats)
        end
    elseif traits.int
        # Solver that do not implement anything other than continuous
        # variables do not need to implement this method, so throw an
        # error if the model has anything but continuous
        error("Solver does not support discrete variables")
    end

    # Provide a primal solution to the solver,
    # if the user has provided a solution or a partial solution.
    if !all(isnan,m.colVal)
        if applicable(MathProgBase.setwarmstart!, m.internalModel, m.colVal)
            if !traits.int || relaxation
                MathProgBase.setwarmstart!(m.internalModel, tidy_warmstart(m))
            else
                # we can pass NaNs through
                MathProgBase.setwarmstart!(m.internalModel, m.colVal)
            end
        else
            suppress_warnings || warn_once("Solver does not appear to support providing initial feasible solutions.")
        end
    end

    # Record that we have a MPB model constructed
    m.internalModelLoaded = true
    nothing
end

# Add the quadratic part of the objective and all quadratic constraints
# to the internal MPB model
function addQuadratics(m::Model)
    # The objective function is always a quadratic expression, but
    # may have no quadratic terms (i.e. be just affine)
    if length(m.obj.qvars1) != 0
        # Check that no coefficients are NaN/Inf
        assert_isfinite(m.obj)
        # Check that quadratic term variables belong to this model
        # Affine portion is checked in prepAffObjective
        if !(verify_ownership(m, m.obj.qvars1) &&
                verify_ownership(m, m.obj.qvars2))
            throw(VariableNotOwnedException("objective"))
        end
        # Check for solver support for quadratic objectives happens in MPB
        MathProgBase.setquadobjterms!(m.internalModel,
            Cint[v.col for v in m.obj.qvars1],
            Cint[v.col for v in m.obj.qvars2], m.obj.qcoeffs)
    end

    # Add quadratic constraint to solver
    sensemap = Dict(:(<=) => '<', :(>=) => '>', :(==) => '=')
    for k in 1:length(m.quadconstr)
        qconstr = m.quadconstr[k]::QuadConstraint
        if !haskey(sensemap, qconstr.sense)
            error("Invalid quadratic constraint sense $(qconstr.sense)")
        end
        s = sensemap[qconstr.sense]

        terms::QuadExpr = qconstr.terms
        # Check that no coefficients are NaN/Inf
        assert_isfinite(terms)
        # Check that quadratic and affine term variables belong to this model
        if !(verify_ownership(m, terms.qvars1) &&
                verify_ownership(m, terms.qvars2) &&
                verify_ownership(m, terms.aff.vars))
            throw(VariableNotOwnedError("quadratic constraint"))
        end
        # Extract indices for MPB, and add the constraint (if we can)
        affidx  = Cint[v.col for v in terms.aff.vars]
        var1idx = Cint[v.col for v in terms.qvars1]
        var2idx = Cint[v.col for v in terms.qvars2]
        if applicable(MathProgBase.addquadconstr!, m.internalModel, affidx, terms.aff.coeffs, var1idx, var2idx, terms.qcoeffs, s, -terms.aff.constant)
            MathProgBase.addquadconstr!(m.internalModel,
                affidx, terms.aff.coeffs,           # aᵀx +
                var1idx, var2idx, terms.qcoeffs,    # xᵀQx
                s, -terms.aff.constant)             # ≤/≥ b
        else
            error("Solver does not support quadratic constraints")
        end
    end
    nothing
end

function addSOS(m::Model)
    for i in 1:length(m.sosconstr)
        sos = m.sosconstr[i]
        indices = Int[v.col for v in sos.terms]
        if sos.sostype == :SOS1
            if applicable(MathProgBase.addsos1!, m.internalModel, indices, sos.weights)
                MathProgBase.addsos1!(m.internalModel, indices, sos.weights)
            else
                error("Solver does not support SOS constraints")
            end
        elseif sos.sostype == :SOS2
            if applicable(MathProgBase.addsos2!, m.internalModel, indices, sos.weights)
                MathProgBase.addsos2!(m.internalModel, indices, sos.weights)
            else
                error("Solver does not support SOS constraints")
            end
        end
    end
end

# Returns coefficients for the affine part of the objective
function prepAffObjective(m::Model)

    # Create dense objective vector
    objaff::AffExpr = m.obj.aff
    # Check that no coefficients are NaN/Inf
    assert_isfinite(objaff)
    if !verify_ownership(m, objaff.vars)
        throw(VariableNotOwnedError("objective"))
    end
    f = zeros(m.numCols)
    @inbounds for ind in 1:length(objaff.vars)
        f[objaff.vars[ind].col] += objaff.coeffs[ind]
    end

    return f
end

# Returns affine constraint lower and upper bounds, all as dense vectors
function prepConstrBounds(m::Model)

    # Create dense affine constraint bound vectors
    linconstr = m.linconstr::Vector{LinearConstraint}
    numRows = length(linconstr)
    # -Inf means no lower bound, +Inf means no upper bound
    rowlb = fill(-Inf, numRows)
    rowub = fill(+Inf, numRows)
    @inbounds for ind in 1:numRows
        rowlb[ind] = linconstr[ind].lb
        rowub[ind] = linconstr[ind].ub
    end

    return rowlb, rowub
end

# Converts all the affine constraints into a sparse column-wise
# matrix of coefficients.
function prepConstrMatrix(m::Model)

    linconstr = m.linconstr::Vector{LinearConstraint}
    numRows = length(linconstr)
    # Calculate the maximum number of nonzeros
    # The actual number may be less because of cancelling or
    # zero-coefficient terms
    nnz = 0
    for c in 1:numRows
        nnz += length(linconstr[c].terms.coeffs)
    end
    # Non-zero row indices
    I = Array{Int}(undef, nnz)
    # Non-zero column indices
    J = Array{Int}(undef, nnz)
    # Non-zero values
    V = Array{Float64}(undef, nnz)

    # Fill it up!
    # Number of nonzeros seen so far
    nnz = 0
    for c in 1:numRows
        # Check that no coefficients are NaN/Inf
        assert_isfinite(linconstr[c].terms)
        coeffs = linconstr[c].terms.coeffs
        vars   = linconstr[c].terms.vars
        # Check that variables belong to this model
        if !verify_ownership(m, vars)
            throw(VariableNotOwnedError("constraint"))
        end
        # Record all (i,j,v) triplets
        @inbounds for ind in 1:length(coeffs)
            nnz += 1
            I[nnz] = c
            J[nnz] = vars[ind].col
            V[nnz] = coeffs[ind]
        end
    end

    # sparse() handles merging duplicate terms and removing zeros
    A = sparse(I,J,V,numRows,m.numCols)
end

function vartypes_without_fixed(m::Model)
    colCats = copy(m.colCat)
    for i in 1:length(colCats)
        if colCats[i] == :Fixed
            @assert m.colLower[i] == m.colUpper[i]
            colCats[i] = :Cont
        end
    end
    return colCats
end

# Collect the terms of the expression `terms` for which the model of the variable is `m`
# into `tmprow`. If the variable of one of the terms does not belong to the model `m` and
# `ignore_not_owned` is `false` then an error is thrown.
function collect_expr!(m::Model, tmprow::IndexedVector, terms::AffExpr, ignore_not_owned::Bool=false)
    empty!(tmprow)
    assert_isfinite(terms)
    coeffs = terms.coeffs
    vars = terms.vars
    # collect duplicates
    for ind in 1:length(coeffs)
        if vars[ind].m === m
            addelt!(tmprow, vars[ind].col, coeffs[ind])
        elseif !ignore_not_owned
            throw(VariableNotOwnedError("constraints"))
        end
    end
    rmz!(tmprow)
    tmprow
end

# Returns a boolean vector indicating if variable in the model
# is an off-diagonal element of an SDP matrix.
# This is needed because we have to rescale coefficients that
# touch these variables.
function offdiagsdpvars(m::Model)
    offdiagvars = falses(m.numCols)
    for (name,idx) in m.varCones
        if name == :SDP
            conelen = length(idx)
            n = round(Int,sqrt(1/4+2*conelen)-1/2)
            @assert n*(n+1)/2 == conelen
            r = 1
            for i in 1:n
                for j in i:n
                    if i != j
                        offdiagvars[idx[r]] = true
                    end
                    r += 1
                end
            end
        end
    end
    return offdiagvars
end

function getSDrowsinfo(m::Model)
    # find starting column indices for sdp matrices
    nnz = 0
    numSDPRows = 0
    numSymRows = 0
    for c in m.sdpconstr
        n = size(c.terms,1)
        @assert n == size(c.terms,2)
        @assert ndims(c.terms) == 2
        numSDPRows += convert(Int, n*(n+1)/2)
        for i in 1:n, j in i:n
            nnz += length(c.terms[i,j].coeffs)
        end
        if !issymmetric(c.terms)
            # symmetry constraints
            numSymRows += convert(Int, n*(n-1)/2)
        end
    end
    numSDPRows, numSymRows, nnz
end

function variable_range_to_cone!(var_cones, m::Model)
    numBounds = 0
    nonNeg  = Int[]
    nonPos  = Int[]
    free    = Int[]
    zeroVar = Int[]
    for i in 1:m.numCols
        seen = false
        lb, ub = m.colLower[i], m.colUpper[i]
        for (_, cone) in m.varCones
            if i in cone
                seen = true
                @assert lb == -Inf && ub == Inf
                break
            end
        end

        if !seen
            if lb != -Inf && lb != 0
                numBounds += 1
            end
            if ub != Inf && ub != 0
                numBounds += 1
            end
            if lb == 0 && ub == 0
                push!(zeroVar, i)
            elseif lb == 0
                push!(nonNeg, i)
            elseif ub == 0
                push!(nonPos, i)
            else
                push!(free, i)
            end
        end
    end

    if !isempty(zeroVar)
        push!(var_cones, (:Zero,zeroVar))
    end
    if !isempty(nonNeg)
        push!(var_cones, (:NonNeg,nonNeg))
    end
    if !isempty(nonPos)
        push!(var_cones, (:NonPos,nonPos))
    end
    if !isempty(free)
        push!(var_cones, (:Free,free))
    end
    numBounds
end

# Represents the constraints `constr` as
# `b - Ax ∈ K`,
# writes the vector `b` of this representation in the argument `b`, starting at index
# `c+1`, and specifies the cone `K` of the corresponding indices in `con_cones`.
# It returns the last index used.
function fillconstrRHS!(b, con_cones, c, constrs::Vector{LinearConstraint})
    nonneg_rows = Int[]
    nonpos_rows = Int[]
    eq_rows     = Int[]

    for con in constrs
        c += 1
        if con.lb == -Inf
            b[c] = con.ub
            push!(nonneg_rows, c)
        elseif con.ub == Inf
            b[c] = con.lb
            push!(nonpos_rows, c)
        elseif con.lb == con.ub
            b[c] = con.lb
            push!(eq_rows, c)
        else
            error("We currently do not support ranged constraints with conic solvers")
        end
    end

    if !isempty(nonneg_rows)
        push!(con_cones, (:NonNeg,nonneg_rows))
    end
    if !isempty(nonpos_rows)
        push!(con_cones, (:NonPos,nonpos_rows))
    end
    if !isempty(eq_rows)
        push!(con_cones, (:Zero,eq_rows))
    end
    c
end

function fillconstrRHS!(b, con_cones, c, socconstr::Vector{SOCConstraint})
    for con in socconstr
        expr = con.normexpr
        c += 1
        soc_start = c
        b[c] = -expr.aff.constant
        for term in expr.norm.terms
            c += 1
            b[c] = expr.coeff*term.constant
        end
        push!(con_cones, (:SOC, soc_start:c))
    end
    c
end

# Represents the constraints `constr` as
# `b - Ax ∈ K`,
# writes the matrix `A` of this representation in the sparse format using `I`, `J` and `V`,
# starting at row index `c+1`.
# It returns the last index used.
function fillconstrLHS!(I, J, V, tmprow::IndexedVector, c, linconstr::Vector{LinearConstraint}, m::Model, ignore_not_owned::Bool=false)
    tmpelts = tmprow.elts
    tmpnzidx = tmprow.nzidx
    for con in linconstr
        c += 1
        collect_expr!(m, tmprow, con.terms, ignore_not_owned)
        nnz = tmprow.nnz
        append!(I, fill(c, nnz))
        indices = tmpnzidx[1:nnz]
        append!(J, indices)
        append!(V, tmpelts[indices])
        empty!(tmprow)
    end
    c
end

function fillconstrLHS!(I, J, V, tmprow::IndexedVector, c, socconstr::Vector{SOCConstraint}, m::Model, ignore_not_owned::Bool=false)
    tmpelts = tmprow.elts
    tmpnzidx = tmprow.nzidx
    for con in socconstr
        c += 1
        expr = con.normexpr
        collect_expr!(m, tmprow, expr.aff, ignore_not_owned)
        nnz = tmprow.nnz
        indices = tmpnzidx[1:nnz]
        append!(I, fill(c, nnz))
        append!(J, indices)
        append!(V, tmpelts[indices])
        for term in expr.norm.terms
            c += 1
            collect_expr!(m, tmprow, term, ignore_not_owned)
            nnz = tmprow.nnz
            indices = tmpnzidx[1:nnz]
            append!(I, fill(c, nnz))
            append!(J, indices)
            append!(V, -expr.coeff*tmpelts[indices])
        end
    end
    c
end

# Represents the constraints `constr` as
# `b - Ax ∈ K`,
# stores the list of rows used for each constraint in
# `constr_to_row` at consecutive indices starting from `d+1`.
# It returns the last row index `c` used and the last index `d` used.
function fillconstrtorow!(constr_to_row, c, d, linconstr::Vector{LinearConstraint})
    for con in linconstr
        c += 1
        d += 1
        constr_to_row[d] = vec(collect(c))
    end
    c, d
end
function fillconstrtorow!(constr_to_row, c, d, socconstr::Vector{SOCConstraint})
    for con in socconstr
        c += 1
        d += 1
        nterms = length(con.normexpr.norm.terms)
        constr_to_row[d] = collect(c:c+nterms)
        c += nterms
    end
    c, d
end

function rescaleSDcols!(f, J, V, m)
    # Objective coefficients and columns of A matrix are
    # rescaled for SDP variables
    offdiagvars = offdiagsdpvars(m)
    f[offdiagvars] /= sqrt(2)
    for k in 1:length(J)
        if offdiagvars[J[k]]
            V[k] /= sqrt(2)
        end
    end
end

# Combination of `fillconstrRHS!`, `fillconstrLHS!` and `fillconstrtorow!`
function fillconstr!(I, J, V, b, con_cones, tmprow::IndexedVector, constr_to_row, c, d, constrs, m, ignore_not_owned::Bool=false)
    fillconstrRHS!(b, con_cones, c, constrs)
    fillconstrLHS!(I, J, V, tmprow, c, constrs, m)
    fillconstrtorow!(constr_to_row, c, d, constrs)
end

function fillconstr!(I, J, V, b, con_cones, tmprow::IndexedVector, constr_to_row, c, d, constrs::Vector{SDConstraint}, m::Model, ignore_not_owned::Bool=false)
    tmpelts = tmprow.elts
    tmpnzidx = tmprow.nzidx
    sdpconstr_sym = Vector{Vector{Tuple{Int,Int}}}(undef, length(constrs))
    sdpidx = 0
    for con in constrs
        sdpidx += 1
        sdp_start = c + 1
        n = size(con.terms,1)
        for i in 1:n, j in i:n
            c += 1
            terms::AffExpr = con.terms[i,j] + con.terms[j,i]
            collect_expr!(m, tmprow, terms, ignore_not_owned)
            nnz = tmprow.nnz
            indices = tmpnzidx[1:nnz]
            append!(I, fill(c, nnz))
            append!(J, indices)
            # scale to svec form
            scale = (i == j) ? 0.5 : 1/sqrt(2)
            append!(V, -scale*tmpelts[indices])
            b[c] = scale*terms.constant
        end
        push!(con_cones, (:SDP, sdp_start:c))
        constr_to_row[d + sdpidx] = collect(sdp_start:c)
        syms = Tuple{Int,Int}[]
        if !issymmetric(con.terms)
            sym_start = c + 1
            # add linear symmetry constraints
            for i in 1:n, j in 1:(i-1)
                collect_expr!(m, tmprow, con.terms[i,j] - con.terms[j,i], ignore_not_owned)
                nnz = tmprow.nnz
                # if the symmetry-enforcing row is empty or has only tiny coefficients due to unintended numerical asymmetry, drop it
                largestabs = 0.0
                for k in 1:nnz
                    largestabs = max(largestabs,abs(tmpelts[tmpnzidx[k]]))
                end
                if largestabs < 1e-10
                    continue
                end
                push!(syms, (i,j))
                c += 1
                indices = tmpnzidx[1:nnz]
                append!(I, fill(c, nnz))
                append!(J, indices)
                append!(V, tmpelts[indices])
                b[c] = 0
            end
            if c >= sym_start
                push!(con_cones, (:Zero, sym_start:c))
            end
            constr_to_row[d + length(constrs) + sdpidx] = collect(sym_start:c)
            @assert length(syms) == length(sym_start:c)
        else
            constr_to_row[d + length(constrs) + sdpidx] = Int[]
        end
        sdpconstr_sym[sdpidx] = syms
    end

    m.sdpconstrSym = sdpconstr_sym

    c, d + 2 * length(constrs)
end

function fill_bounds_constr!(I, J, V, b, con_cones, constr_to_row, c, d, m)
    nonneg_rows = Int[]
    nonpos_rows = Int[]

    for idx in 1:m.numCols
        lb = m.colLower[idx]
        if lb != -Inf && lb != 0
            c   += 1
            d   += 1
            push!(I, c)
            push!(J, idx)
            push!(V, 1.0)
            b[c] = lb
            push!(nonpos_rows, c)
            constr_to_row[d] = vec(collect(c))
        end
        ub = m.colUpper[idx]
        if ub != Inf && ub != 0
            c += 1
            d += 1
            push!(I, c)
            push!(J, idx)
            push!(V, 1.0)
            b[c] = ub
            push!(nonneg_rows, c)
            constr_to_row[d] = vec(collect(c))
        end
    end

    if !isempty(nonneg_rows)
        push!(con_cones, (:NonNeg,nonneg_rows))
    end
    if !isempty(nonpos_rows)
        push!(con_cones, (:NonPos,nonpos_rows))
    end

    c, d
end

function conicdata(m::Model)
    var_cones = Any[cone for cone in m.varCones]
    con_cones = Any[]
    nnz = 0

    numSDPRows, numSymRows, nnz = getSDrowsinfo(m)

    linconstr = m.linconstr::Vector{LinearConstraint}
    numLinRows = length(linconstr)

    numBounds = variable_range_to_cone!(var_cones, m)

    nnz += numBounds
    for c in 1:numLinRows
        nnz += length(linconstr[c].terms.coeffs)
    end

    numSOCRows = getNumSOCRows(m)
    numNormRows = length(m.socconstr)

    numRows = numLinRows + numBounds + numSOCRows + numSDPRows + numSymRows

    # should maintain the order of constraints in the above form
    # throughout the code c is the conic constraint index
    constr_to_row = Array{Vector{Int}}(undef, numLinRows + numBounds + numNormRows + 2*length(m.sdpconstr))

    b = Array{Float64}(undef, numRows)

    I = Int[]
    J = Int[]
    V = Float64[]
    sizehint!(I, nnz)
    sizehint!(J, nnz)
    sizehint!(V, nnz)

    # Fill it up
    tmprow = IndexedVector(Float64, m.numCols)

    c, d = fillconstr!(I, J, V, b, con_cones, tmprow, constr_to_row, 0, 0, m.linconstr, m)

    @assert c == numLinRows
    @assert d == numLinRows

    c, d = fill_bounds_constr!(I, J, V, b, con_cones, constr_to_row, c, d, m)

    @assert c == numLinRows + numBounds
    @assert d == numLinRows + numBounds

    c, d = fillconstr!(I, J, V, b, con_cones, tmprow, constr_to_row, c, d, m.socconstr, m)

    @assert c == numLinRows + numBounds + numSOCRows
    @assert d == numLinRows + numBounds + numNormRows

    c, d = fillconstr!(I, J, V, b, con_cones, tmprow, constr_to_row, c, d, m.sdpconstr, m)

    if c < length(b)
        # This happens for example when symmetry constraints are dropped with SDP
        resize!(b, c)
    end

    m.constr_to_row = constr_to_row

    f = prepAffObjective(m)

    # The conic MPB interface defines conic problems as
    # always being minimization problems, so flip if needed
    m.objSense == :Max && rmul!(f, -1.0)

    rescaleSDcols!(f, J, V, m)

    A = sparse(I, J, V, c, m.numCols)
    # @show full(A), b
    # @show var_cones, con_cones

    # TODO: uncomment these lines when they work with Mosek
    # supported = MathProgBase.supportedcones(m.internalModel)
    # @assert (:NonNeg in supported) && (:NonPos in supported) && (:Free in supported) && (:SDP in supported)
    f, A, b, var_cones, con_cones
end

constraintbounds(m::Model) = constraintbounds(m, ProblemTraits(m))

function constraintbounds(m::Model,traits::ProblemTraits)

    if traits.conic
        error("Not implemented for conic problems")
    elseif traits.sos
        error("Not implemented for SOS constraints")
    end

    linobj = prepAffObjective(m)
    linrowlb, linrowub = prepConstrBounds(m)

    quadrowlb = Float64[]
    quadrowub = Float64[]
    for c::QuadConstraint in m.quadconstr
        if c.sense == :(<=)
            push!(quadrowlb, -Inf)
            push!(quadrowub, 0.0)
        elseif c.sense == :(>=)
            push!(quadrowlb, 0.0)
            push!(quadrowub, Inf)
        elseif c.sense == :(==)
            push!(quadrowlb, 0.0)
            push!(quadrowub, 0.0)
        else
            error("Unrecognized quadratic constraint sense $(c.sense)")
        end
    end

    nlrowlb = Float64[]
    nlrowub = Float64[]

    if traits.nlp
        nldata::NLPData = m.nlpdata
        for c in nldata.nlconstr
            push!(nlrowlb, c.lb)
            push!(nlrowub, c.ub)
        end
    end

    lb = [linrowlb;quadrowlb;nlrowlb]
    ub = [linrowub;quadrowub;nlrowub]

    return lb, ub

end

# for continuous problems we probably don't want to pass NaNs to the solvers
function tidy_warmstart(m::Model)
    if !any(isnan, m.colVal)
        return m.colVal
    else
        initval = copy(m.colVal)
        initval[isnan.(m.colVal)] .= 0
        return initval
    end
end


# returns (unsorted) column indices and coefficient terms for merged vector
# assume that v is zero'd
function merge_duplicates(::Type{IntType},aff::GenericAffExpr{CoefType,Variable}, v::IndexedVector{CoefType}, m::Model) where {CoefType,IntType<:Integer}
    resize!(v, m.numCols)
    for ind in 1:length(aff.coeffs)
        var = aff.vars[ind]
        var.m === m || error("Variable does not belong to this model")
        addelt!(v, aff.vars[ind].col, aff.coeffs[ind])
    end
    rmz!(v)
    indices = Array{IntType}(undef, v.nnz)
    coeffs = Array{CoefType}(undef, v.nnz)
    for i in 1:v.nnz
        idx = v.nzidx[i]
        indices[i] = idx
        coeffs[i] = v.elts[idx]
    end
    empty!(v)

    return indices, coeffs

end
