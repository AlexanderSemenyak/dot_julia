#_global_mt_setting = true

# Evaluate code either multi-threaded or single-threaded dependent on the global multithreading setting.
# TODO: Remove, find cleaner solution.
macro mt(expr)
    quote
        if _global_mt_setting
            @onthreads mt_nthreads() begin
                $(esc(expr))
            end
        else
            $(esc(expr))
        end
    end
end

function mt_nthreads()
    _global_mt_setting ? allthreads() : 1
end
const _minpoints_per_dimension = 50


"""
function hm_integrate!(result, settings = HMIPrecisionSettings())

This function starts the adaptive harmonic mean integration. See arXiv:1808.08051 for more details.
It needs a HMIData struct as input, which holds the samples, in form of a dataset, the integration volumes and other
properties, required for the integration, and the final result.
"""
function hm_integrate!(
    result::HMIData{T, I, V},
    integrationvol::Symbol = :HyperRectangle;
    settings::HMISettings = HMIPrecisionSettings())::HMIData{T, I, V} where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    hm_init(result, settings)

    hm_whiteningtransformation!(result, settings)

    hm_createpartitioningtree!(result)

    notsinglemode = hm_findseeds!(result, settings)

    if !notsinglemode
        result.dataset1.tolerance = Inf
        result.dataset2.tolerance = Inf
        @log_msg LOG_WARNING "Tolerance set to Inf for single mode distributions"
    else
        hm_determinetolerance!(result, settings)
    end

    hm_create_integrationvolumes!(result, settings)
    hm_integrate_integrationvolumes!(result, settings)

    for pair in settings.uncertainty_estimators
        @log_msg LOG_INFO "Estimating Uncertainty ($(pair[1]))"
        result.integralestimates[pair[1]] = pair[2](result)
    end

    #Possible Uncertainty Estimators:
    #hm_combineresults_legacy!      see my master thesis for details
    #hm_combineresults_covweighted!  see arXiv:1808.08051 for details
    #hm_combineresults_analyticestimation! based on analytic uncertainty of both Z (see thesis) and r (binomial error)

    result
end


ahmi_integrate(samples::DensitySampleVector) = hm_integrate!(HMIData(samples))


"""
function hm_init!(result, settings)

Sets the global multithreading setting and ensures that a minimum number of samples, dependent on the number of dimensions, are provided.
"""
function hm_init(
    result::HMIData{T, I, V},
    settings::HMISettings) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    if result.dataset1.N < result.dataset1.P * _minpoints_per_dimension || result.dataset2.N < result.dataset2.P * _minpoints_per_dimension
        @log_msg LOG_ERROR "Not enough samples for integration"
    end
    @assert result.dataset1.P == result.dataset2.P

    global _global_mt_setting = settings.useMultiThreading

    @log_msg LOG_INFO "Harmonic Mean Integration started. Samples in dataset 1 / 2: \t$(result.dataset1.N) / $(result.dataset2.N)\tParameters:\t$(result.dataset1.P)"
end

"""
function hm_whiteningtransformation!(result, settings)

Applies a whitening transformation to the samples. A custom whitening method can be used by overriding settings.whitening_function!
"""
function hm_whiteningtransformation!(
    result::HMIData{T, I, V},
    settings::HMISettings) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    if !isinitialized(result.whiteningresult)
        @log_msg LOG_INFO "Data Whitening."
        result.whiteningresult = settings.whitening_function!(result.dataset1)
    end

    if !result.dataset1.iswhitened
        @log_msg LOG_INFO "Apply Whitening Transformation to Data Set 1"
        transform_data!(result.dataset1, result.whiteningresult.whiteningmatrix, result.whiteningresult.meanvalue, false)
    end
    if !result.dataset2.iswhitened
        @log_msg LOG_INFO "Apply Whitening Transformation to Data Set 2"
        transform_data!(result.dataset2, result.whiteningresult.whiteningmatrix, result.whiteningresult.meanvalue, true)
    end
end

function hm_createpartitioningtree!(
    result::HMIData{T, I, V}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    maxleafsize = 200
    progress_steps = ((!isinitialized(result.dataset1.partitioningtree) ? result.dataset1.N / maxleafsize : 0.0)
                    + (!isinitialized(result.dataset2.partitioningtree) ? result.dataset2.N / maxleafsize : 0.0))
    progressbar = Progress(round(Int64, progress_steps))
    progress_steps > 0 && @log_msg LOG_INFO "Create Space Partitioning Tree"
    !isinitialized(result.dataset1.partitioningtree) && create_search_tree(result.dataset1, progressbar, maxleafsize = maxleafsize)
    !isinitialized(result.dataset2.partitioningtree) && create_search_tree(result.dataset2, progressbar, maxleafsize = maxleafsize)
    finish!(progressbar)
end

function hm_findseeds!(
    result::HMIData{T, I, V},
    settings::HMISettings) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    #if hyper-rectangles are already created and only need to be populated using different data sets
    if !isempty(result.volumelist1) && !isempty(result.volumelist2)
        return true
    end

    notsinglemode = true
    @log_msg LOG_INFO "Determine Hyperrectangle Starting Samples"
    if isempty(result.dataset1.startingIDs)
        notsinglemode &= find_hypercube_centers(result.dataset1, result.whiteningresult, settings)
    end
    if isempty(result.dataset2.startingIDs)
        notsinglemode &= find_hypercube_centers(result.dataset2, result.whiteningresult, settings)
    end

    notsinglemode
end

function hm_determinetolerance!(
    result::HMIData{T, I, V},
    settings::HMISettings) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    #if hyper-rectangles are already created and only need to be populated using different data sets
    if !isempty(result.volumelist1) && !isempty(result.volumelist2)
        return
    end

    (iszero(result.dataset1.tolerance) || iszero(result.dataset2.tolerance)) && @log_msg LOG_INFO "Determine Tolerances for Hyperrectangle Creation"

    if iszero(result.dataset1.tolerance)
        suggTolPts = max(result.dataset1.P * 4, ceil(I, sqrt(result.dataset1.N)))
        findtolerance(result.dataset1, min(10, settings.warning_minstartingids), suggTolPts)
        @log_msg LOG_DEBUG "Tolerance Data Set 1: $(result.dataset1.tolerance)"
    end
    if iszero(result.dataset2.tolerance)
        suggTolPts = max(result.dataset2.P * 4, ceil(I, sqrt(result.dataset2.N)))
        findtolerance(result.dataset2, min(10, settings.warning_minstartingids), suggTolPts)
        @log_msg LOG_DEBUG "Tolerance Data Set 2: $(result.dataset2.tolerance)"
    end
end



function hm_combineresults_legacy!(result::HMIData{T, I, V}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}
    result_legacy = HMIResult(T)
    result_legacy.result1, result_legacy.dat2 = hm_combineresults_legacy_dataset!(result.dataset1, result.integrals2, result.volumelist2)
    result_legacy.result2, result_legacy.dat2 = hm_combineresults_legacy_dataset!(result.dataset2, result.integrals1, result.volumelist1)
    result_legacy.final = HMIEstimate(result_legacy.result1, result_legacy.result2)

    result_legacy
end

function hm_combineresults_legacy_dataset!(
    dataset::DataSet{T, I},
    integralestimates::IntermediateResults{T},
    volumes::Array{IntegrationVolume{T, I, V}, 1}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    dat = Dict{String, Any}()

    pweights = create_pointweights(dataset, volumes, integralestimates.volumeID)

    weights_overlap::Array{T, 1} = zeros(T, length(integralestimates))

    for i = 1:length(integralestimates)
        vol_id = integralestimates.volumeID[i]
        trw = sum(dataset.weights[volumes[vol_id].pointcloud.pointIDs])
        for id in eachindex(volumes[vol_id].pointcloud.pointIDs)
            weights_overlap[i] += 1.0 / trw / pweights[volumes[vol_id].pointcloud.pointIDs[id]]
        end
    end

    M = length(integralestimates)

    i_std = mean(integralestimates.integrals, ProbabilityWeights(weights_overlap))
    e_std = sqrt(var(integralestimates.integrals) / sum(weights_overlap))

    HMIEstimate(i_std, e_std, weights_overlap), dat
end

function hm_combineresults_covweighted!(result::HMIData{T, I, V}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}
    result_covweighted = HMIResult(T)
    result_covweighted.result1, result_covweighted.dat1 = hm_combineresults_covweighted_dataset!(result.dataset1,
        result.integrals2, result.volumelist2)
    result_covweighted.result2, result_covweighted.dat2 = hm_combineresults_covweighted_dataset!(result.dataset2,
        result.integrals1, result.volumelist1)
    result_covweighted.final = HMIEstimate(result_covweighted.result1, result_covweighted.result2)

    result_covweighted
end

function hm_combineresults_covweighted_dataset!(
    dataset::DataSet{T, I},
    integralestimates::IntermediateResults{T},
    volumes::Array{IntegrationVolume{T, I, V}, 1}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    dat = Dict{String, Any}()
    M = length(integralestimates)

    dat["Σ"] = Σ = cov(integralestimates.Y) ./ dataset.nsubsets

    weights_cov = 1 ./ diag(Σ)
    weights_cov /= sum(weights_cov)

    i_cov = mean(integralestimates.integrals, AnalyticWeights(weights_cov))

    e_cov = 0.0
    for i=1:M
        for j=1:M
            e_cov += weights_cov[i] * weights_cov[j] * Σ[i, j]
        end
    end

    HMIEstimate(i_cov, sqrt(e_cov), weights_cov), dat
end

function hm_combineresults_analyticestimation!(result::HMIData{T, I, V}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}
    result_analytic = HMIResult(T)
    result_analytic.result1, result_analytic.dat1 = hm_combineresults_analyticestimation_dataset!(result.dataset1,
        result.whiteningresult.determinant, result.integrals2, result.volumelist2)
    result_analytic.result2, result_analytic.dat2 = hm_combineresults_analyticestimation_dataset!(result.dataset2,
        result.whiteningresult.determinant, result.integrals1, result.volumelist1)
    result_analytic.final = HMIEstimate(result_analytic.result1, result_analytic.result2)

    result_analytic
end

function hm_combineresults_analyticestimation_dataset!(
    dataset::DataSet{T, I},
    determinant::T,
    integralestimates::IntermediateResults{T},
    volumes::Array{IntegrationVolume{T, I, V}, 1}) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    dat = Dict{String, Any}()

    uncertainty_r = Array{T, 1}(undef, length(integralestimates.integrals))
    uncertainty_Y = Array{T, 1}(undef, length(integralestimates.integrals))
    uncertainty_tot = Array{T, 1}(undef, length(integralestimates.integrals))
    f_min = Array{T, 1}(undef, length(integralestimates.integrals))
    f_max = Array{T, 1}(undef, length(integralestimates.integrals))
    μ_Z = Array{T, 1}(undef, length(integralestimates.integrals))
    σ_μZ_sq = Array{T, 1}(undef, length(integralestimates.integrals))
    integral1 = Array{T, 1}(undef, length(integralestimates.integrals))
    integral2 = Array{T, 1}(undef, length(integralestimates.integrals))
    ess = Array{T, 1}(undef, length(integralestimates.integrals))

    wp_integralestimates = workpart(integralestimates.integrals, ParallelProcessingTools.workers(), ParallelProcessingTools.myid())
    @mt for i in workpart(eachindex(wp_integralestimates), mt_nthreads(), threadid())
        uncertainty_r[i], uncertainty_Y[i], uncertainty_tot[i], f_min[i], f_max[i], μ_Z[i], σ_μZ_sq[i], integral1[i], integral2[i], ess[i] =
            calculateuncertainty(dataset, volumes[integralestimates.volumeID[i]], determinant, integralestimates.integrals[i])
    end

    dat["uncertainty_r"] = uncertainty_r
    dat["uncertainty_Y"] = uncertainty_Y
    dat["uncertainty_tot"] = uncertainty_tot
    dat["f_min"] = f_min
    dat["f_max"] = f_max
    dat["μ_Z"] = μ_Z
    dat["σ_μZ_sq"] = σ_μZ_sq
    dat["integral1_sq_cuba"] = integral1
    dat["integral2_cuba"] = integral2
    dat["ess"] = ess

    weights_cov = 1 ./ uncertainty_tot
    weights_cov /= sum(weights_cov)

    i_cov = mean(integralestimates.integrals, AnalyticWeights(weights_cov))

    dat["overlap"] = overlap = calculate_overlap(dataset, volumes, integralestimates)
    M = length(integralestimates)

    Σ = Array{T, 2}(undef, M, M)
    for i=1:M
        for j=1:M
            Σ[i,j] =  uncertainty_tot[i] * uncertainty_tot[j] * overlap[i, j]
        end
    end
    dat["Σ"] = Σ

    e_cov = 0.0
    for i=1:M
        for j=1:M
            e_cov += weights_cov[i] * weights_cov[j] * Σ[i, j]
        end
    end

    HMIEstimate(i_cov, sqrt(e_cov), weights_cov), dat

end

function findtolerance(
    dataset::DataSet{T, I},
    ntestcubes::I,
    pts::I) where {T<:AbstractFloat, I<:Integer}

    ntestpts = [2, 4, 8] * pts
    @log_msg LOG_TRACE "Tolerance Test Cube Points: $([pts, ntestpts...])"

    vInc = zeros(T, ntestcubes * (length(ntestpts) + 1))
    pInc = zeros(T, ntestcubes * (length(ntestpts) + 1))

    startingIDs = dataset.startingIDs

    cntr = 1
    for id = 1:ntestcubes
        c = find_density_test_cube(dataset.data[:, startingIDs[id]], dataset, pts)
        prevv = c[1]^dataset.P
        prevp = c[2].pointcloud.points
        for i in ntestpts
            c = find_density_test_cube(dataset.data[:, startingIDs[id]], dataset, i)
            v = c[1]^dataset.P
            p = c[2].pointcloud.points

            vInc[cntr] = v/prevv
            pInc[cntr] = p/prevp
            cntr += 1
            prevv = v
            prevp = p
        end
    end
    tols = vInc ./ pInc

    i = length(tols)
    while i > 0
        if isnan(tols[i]) || isinf(tols[i]) || tols[i] <= 1.0
            deleteat!(tols, i)
        end
        i -= 1
    end

    @log_msg LOG_TRACE "Tolerance List: $tols"

    suggTol::T = if length(tols) < 4
        @log_msg LOG_WARNING "Tolerance calculation failed. Tolerance is set to default to 1.5"
        3
    else
        (mean(trim(tols)) - 1) * 4 +1
    end

    dataset.tolerance = suggTol
end


function hm_integrate_integrationvolumes!(
    result::HMIData{T, I, V},
    settings::HMISettings) where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    nRes = length(result.volumelist1) + length(result.volumelist2)
    @log_msg LOG_INFO "Integrating $nRes Hyperrectangles"

    progressbar = Progress(nRes)

    result.integrals1, result.rejectedrects1 = hm_integrate_integrationvolumes!_dataset(result.volumelist1, result.dataset2, result.whiteningresult.determinant, progressbar, settings)
    result.integrals2, result.rejectedrects2 = hm_integrate_integrationvolumes!_dataset(result.volumelist2, result.dataset1, result.whiteningresult.determinant, progressbar, settings)

    finish!(progressbar)
end


function hm_integrate_integrationvolumes!_dataset(
    volumes::Array{IntegrationVolume{T, I, V}},
    dataset::DataSet{T, I},
    determinant::T,
    progressbar::Progress,
    settings::HMISettings)::Tuple{IntermediateResults{T}, Vector{I}} where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    if length(volumes) < 1
        @log_msg LOG_ERROR "No hyper-rectangles could be created. Try integration with more points or different settings."
    end

    integralestimates = IntermediateResults(T, length(volumes))
    integralestimates.Y = zeros(T, dataset.nsubsets, length(volumes))

    wp_volumes = workpart(volumes, ParallelProcessingTools.workers(), ParallelProcessingTools.myid())
    @mt for i in workpart(eachindex(wp_volumes), mt_nthreads(), threadid())
        integralestimates.Y[:, i], integralestimates.integrals[i] = integrate_hyperrectangle_cov(dataset, volumes[i], determinant)

        lock(BAT.Logging._global_lock) do
            next!(progressbar)
        end
    end

    rejectedids = trim(integralestimates, settings.dotrimming)

    return integralestimates, rejectedids
end



function integrate_hyperrectangle_cov(
    dataset::DataSet{T, I},
    integrationvol::IntegrationVolume{T, I, V},
    determinant::T)::Tuple{Array{T, 1}, T} where {T<:AbstractFloat, I<:Integer, V<:SpatialVolume}

    norm_const = zeros(T, dataset.nsubsets)
    totalWeights = zeros(T, dataset.nsubsets)

    for i in eachindex(dataset.weights)
        totalWeights[dataset.ids[i]] += dataset.weights[i]
    end

    s = zeros(T, dataset.nsubsets)
    s_sum = T(0)
    nsamples = zeros(T, dataset.nsubsets)
    for id in integrationvol.pointcloud.pointIDs
        prob = dataset.logprob[id] - integrationvol.pointcloud.maxLogProb
        s[dataset.ids[id]] += T(1) / exp(prob) * dataset.weights[id]
        s_sum += T(1) / exp(prob) * dataset.weights[id]
        nsamples[dataset.ids[id]] += T(1)
    end

    for n = 1:dataset.nsubsets
        norm_const[n] = totalWeights[n] * integrationvol.volume / determinant / exp(-integrationvol.pointcloud.maxLogProb)
    end

    integral::T = sum(dataset.weights) * integrationvol.volume / s_sum / determinant / exp(-integrationvol.pointcloud.maxLogProb)
    integrals_batches = norm_const ./ s

    #replace INF entries with mean integral value
    for i in eachindex(integrals_batches)
        if isnan(integrals_batches[i]) || isinf(integrals_batches[i])
            integrals_batches[i] = integral
        end
    end

    return integrals_batches, integral
end
