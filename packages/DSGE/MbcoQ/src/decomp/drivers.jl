"""
```
decompose_forecast(m_new, m_old, df_new, df_old, input_type, cond_new, cond_old,
    classes; verbose = :low, kwargs...)

decompose_forecast(m_new, m_old, df_new, df_old, params_new, params_old,
    cond_new, cond_old, classes; check = false)
```

### Inputs

- `m_new::M` and `m_old::M` where `M<:AbstractModel`
- `df_new::DataFrame` and `df_old::DataFrame`
- `cond_new::Symbol` and `cond_old::Symbol`
- `classes::Vector{Symbol}`: some subset of `[:states, :obs, :pseudo]`

**Method 1 only:**

- `input_type::Symbol`: estimation type to use. Parameters will be loaded using
  `load_draws(m_new, input_type)` and `load_draws(m_old, input_type)` in this
  method

**Method 2 only:**

- `params_new::Vector{Float64}` and `params_old::Vector{Float64}`: single
  parameter draws to use

### Keyword Arguments

- `check::Bool`: whether to check that the individual components add up to the
  correct total difference in forecasts. This roughly doubles the runtime

**Method 1 only:**

- `verbose::Symbol`

### Outputs

The first method returns nothing. The second method returns
`decomp::Dict{Symbol, Matrix{Float64}}`, which has keys of the form
`:decomp<component><class>` and values of size `Ny` x `Nh`, where

- `Ny` is the number of variables in the given class
- `Nh` is the number of common forecast periods, i.e. periods between
  `date_forecast_start(m_new)` and `date_forecast_end(m_old)`
"""
function decompose_forecast(m_new::M, m_old::M, df_new::DataFrame, df_old::DataFrame,
                            input_type::Symbol, cond_new::Symbol, cond_old::Symbol,
                            classes::Vector{Symbol};
                            verbose::Symbol = :low, forecast_string_new = "", forecast_string_old = "", kwargs...) where M<:AbstractModel
    # Get output file names
    decomp_output_files = get_decomp_output_files(m_new, m_old, input_type, cond_new, cond_old, classes, forecast_string_old = forecast_string_old, forecast_string_new = forecast_string_new)

    info_print(verbose, :low, "Decomposing forecast...")
    println(verbose, :low, "Start time: $(now())")

    # Set up call to lower-level method
    f(params_new::Vector{Float64}, params_old::Vector{Float64}) =
      decompose_forecast(m_new, m_old, df_new, df_old, params_new, params_old,
                         cond_new, cond_old, classes; kwargs...)

    # Single-draw forecasts
    if input_type in [:mode, :mean, :init]

        params_new = load_draws(m_new, input_type, verbose = verbose)
        params_old = load_draws(m_old, input_type, verbose = verbose)
        decomps = f(params_new, params_old)
        write_forecast_decomposition(m_new, m_old, input_type, classes, decomp_output_files, decomps,
                                     forecast_string_new = forecast_string_new, forecast_string_old = forecast_string_old,
                                     verbose = verbose)

    # Multiple-draw forecasts
    elseif input_type == :full

        block_inds, block_inds_thin = forecast_block_inds(m_new, input_type)
        nblocks = length(block_inds)
        total_forecast_time = 0.0

        for block = 1:nblocks
            println(verbose, :low)
            info_print(verbose, :low, "Decomposing block $block of $nblocks...")
            begin_time = time_ns()

            # Get to work!
            params_new = load_draws(m_new, input_type, block_inds[block], verbose = verbose)
            params_old = load_draws(m_old, input_type, block_inds[block], verbose = verbose)
            mapfcn = use_parallel_workers(m_new) ? pmap : map
            decomps = mapfcn(f, params_new, params_old)

            # Assemble outputs from this block and write to file
            decomps = convert(Vector{Dict{Symbol, Array{Float64}}}, decomps)
            decomps = assemble_block_outputs(decomps)
            write_forecast_decomposition(m_new, m_old, input_type, classes, decomp_output_files, decomps,
                                         block_number = Nullable(block), block_inds = block_inds_thin[block],
                                         forecast_string_new = forecast_string_new, forecast_string_old = forecast_string_old,
                                         verbose = verbose)
            gc()

            # Calculate time to complete this block, average block time, and
            # expected time to completion
            block_time = (time_ns() - begin_time)/1e9
            total_forecast_time += block_time
            total_forecast_time_min     = total_forecast_time/60
            expected_time_remaining     = (total_forecast_time/block)*(nblocks - block)
            expected_time_remaining_min = expected_time_remaining/60

            println(verbose, :low, "\nCompleted $block of $nblocks blocks.")
            println(verbose, :low, "Total time elapsed: $total_forecast_time_min minutes")
            println(verbose, :low, "Expected time remaining: $expected_time_remaining_min minutes")
        end # of loop through blocks

    else
        error("Invalid input_type: $input_type. Must be in [:mode, :mean, :init, :full]")
    end

    combine_raw_forecast_output_and_metadata(m_new, decomp_output_files, verbose = verbose)

    println(verbose, :low, "\nForecast decomposition complete: $(now())")
end

function decompose_forecast(m_new::M, m_old::M, df_new::DataFrame, df_old::DataFrame,
                            params_new::Vector{Float64}, params_old::Vector{Float64},
                            cond_new::Symbol, cond_old::Symbol, classes::Vector{Symbol};
                            check::Bool = false, forecast_string_old = "", forecast_string_new = "") where M<:AbstractModel
    # Check numbers of periods
    T, k, H = decomposition_periods(m_new, m_old, df_new, df_old, cond_new, cond_old)

    # Forecast
    f(m::AbstractModel, df::DataFrame, params::Vector{Float64}, cond_type::Symbol; kwargs...) =
        decomposition_forecast(m, df, params, cond_type, T, k, H;
                               kwargs..., check = check)

    out1 = f(m_new, df_new, params_new, cond_new, outputs = [:shockdec])            # new data, new params
    out2 = f(m_old, df_old, params_new, cond_old, outputs = [:shockdec, :forecast]) # old data, new params
    out3 = f(m_old, df_old, params_old, cond_old, outputs = [:forecast])            # old data, old params

    # Initialize output dictionary
    decomp = Dict{Symbol, Array{Float64}}()

    # Decomposition
    for class in classes
        # All elements of out are of size Ny x Nh, where the second dimension
        # ranges from t = T+1:T+H
        forecastvar = Symbol(:histforecast, class) # Z s_{T+h} + D
        trendvar    = Symbol(:trend,        class) # Z D
        dettrendvar = Symbol(:dettrend,     class) # Z T^{T+h} s_0 + D
        shockdecvar = Symbol(:shockdec,     class) # Z \sum_{t=1}^{T+h} T^{T+h-t} R ϵ_t + D
        datavar     = Symbol(:data,         class) # Z \sum_{t=1}^{T-k} T^{T+h-t} R ϵ_t + D
        newsvar     = Symbol(:news,         class) # Z \sum_{t=T-k+1}^{T+h} T^{T+h-t} R ϵ_t + D

        # 1(a). Data revision and news
        data_comp = (out1[dettrendvar] - out2[dettrendvar]) + (out1[datavar] - out2[datavar])
        decomp[Symbol(:decompdata, class)] = data_comp

        news_comp = out1[newsvar] - out2[newsvar]
        decomp[Symbol(:decompnews, class)] = news_comp

        # 1(b). Shock decomposition and deterministic trend
        shockdec_comp = out1[shockdecvar] - out2[shockdecvar] # Ny x Nh x Ne
        decomp[Symbol(:decompshockdec, class)] = shockdec_comp

        dettrend_comp = out1[dettrendvar] - out2[dettrendvar]
        decomp[Symbol(:decompdettrend, class)] = dettrend_comp

        # Check that 1(a) and 1(b) are equal
        check && @assert dettrend_comp + dropdims(sum(shockdec_comp, dims = 3), dims = 3) ≈ data_comp + news_comp

        # 2. Parameter re-estimation
        para_comp = out2[forecastvar] - out3[forecastvar]
        decomp[Symbol(:decomppara, class)] = para_comp

        # 1 + 2. Total difference
        total_diff = para_comp + data_comp + news_comp
        decomp[Symbol(:decomptotal, class)] = total_diff
        check && @assert total_diff ≈ out1[forecastvar] - out3[forecastvar]
    end

    return decomp
end

"""
```
decomposition_periods(m_new, m_old, df_new, df_old, cond_new, cond_old)
```

Returns `T`, `k`, and `H`, where:

- New model has `T` periods of data
- Old model has `T-k` periods of data
- Old and new models both forecast up to `T+H`
"""
function decomposition_periods(m_new::M, m_old::M, df_new::DataFrame, df_old::DataFrame,
                               cond_new::Symbol, cond_old::Symbol) where M<:AbstractModel
    # Number of presample periods T0 must be the same
    T0 = n_presample_periods(m_new)
    @assert n_presample_periods(m_old) == T0

    # New model has T main-sample periods
    # Old model has T-k main-sample periods
    T = n_mainsample_periods(m_new)
    k = subtract_quarters(date_forecast_start(m_new), date_forecast_start(m_old))
    @assert k >= 0

    # Number of conditional periods T1 may differ
    T1_new = cond_new == :none ? 0 : n_conditional_periods(m_new)
    T1_old = cond_old == :none ? 0 : n_conditional_periods(m_old)

    # Check DataFrame sizes
    @assert size(df_new, 1) == T0 + T + T1_new
    @assert size(df_old, 1) == T0 + T - k + T1_old

    # Old model forecasts up to T+H
    H = subtract_quarters(date_forecast_end(m_old), date_mainsample_end(m_new))

    return T, k, H
end

"""
```
decomposition_forecast(m, df, params, cond_type, keep_startdate, keep_enddate, shockdec_splitdate;
    outputs = [:forecast, :shockdec], check = false)
```

Equivalent of `forecast_one_draw` for forecast decomposition. `keep_startdate =
date_forecast_start(m_new)` corresponds to time T+1, `keep_enddate =
date_forecast_end(m_old)` to time T+H, and `shockdec_splitdate =
date_mainsample_end(m_old)` to time T-k.

Returns `out::Dict{Symbol, Array{Float64}}`, which has keys determined as follows:

- If `:forecast in outputs` or `check = true`:
  - `:forecast<class>`

- If `:shockdec in outputs`:
  - `:trend<class>`
  - `:dettrend<class>`
  - `:data<class>`: like a shockdec, but only applying smoothed shocks up to `shockdec_splitdate`
  - `:news<class>`: like a shockdec, but only applying smoothed shocks after `shockdec_splitdate`
"""
function decomposition_forecast(m::AbstractModel, df::DataFrame, params::Vector{Float64}, cond_type::Symbol,
                                T::Int, k::Int, H::Int;
                                outputs::Vector{Symbol} = [:forecast, :shockdec], check::Bool = false)
    # Compute state space
    update!(m, params)
    system = compute_system(m)

    # Initialize output dictionary
    out = Dict{Symbol, Array{Float64}}()

    # Smooth and forecast
    histstates, histshocks, histpseudo, s_0 = smooth(m, df, system, cond_type = cond_type, draw_states = false)
    histobs = system[:ZZ] * histstates .+ system[:DD]

    if :forecast in outputs || check
        s_T = histstates[:, end]
        _, forecastobs, forecastpseudo, _ =
            forecast(m, system, s_T, cond_type = cond_type, enforce_zlb = false, draw_shocks = false)

        out[:histforecastobs]    = hcat(histobs,    forecastobs)[:, 1:T+H]
        out[:histforecastpseudo] = hcat(histpseudo, forecastpseudo)[:, 1:T+H]
    end

    # Compute trend, dettrend, and shockdecs
    if :shockdec in outputs
        nstates = n_states_augmented(m)
        nshocks = n_shocks_exogenous(m)

        _, out[:trendobs],    out[:trendpseudo]    = trends(system)
        _, out[:dettrendobs], out[:dettrendpseudo] = deterministic_trends(system, s_0, T+H, 1, T+H)

        # Applying all shocks
        _, out[:shockdecobs], out[:shockdecpseudo] =
            shock_decompositions(system, forecast_horizons(m), histshocks, 1, T+H)

        # Applying ϵ_{1:T-k} and ϵ_{T-k+1:end}
        system0 = zero_system_constants(system)

        data_shocks = zeros(nshocks, T+H)
        data_shocks[:, 1:T-k] = histshocks[:, 1:T-k]
        _, out[:dataobs], out[:datapseudo], _ = forecast(system0, zeros(nstates), data_shocks)

        Tstar = size(histshocks, 2) # either T or T+1
        news_shocks = zeros(nshocks, T+H)
        news_shocks[:, T-k+1:Tstar] = histshocks[:, T-k+1:Tstar]
        _, out[:newsobs], out[:newspseudo], _ = forecast(system0, zeros(nstates), news_shocks)
    end

    # Return
    return out
end
