"""
```
plot_history_and_forecast(m, var, class, input_type, cond_type;
    title = "", plot_handle = plot(), kwargs...)

plot_history_and_forecast(m, vars, class, input_type, cond_type;
    forecast_string = "", bdd_and_unbdd = false,

    plotroot = figurespath(m, \"forecast\"), titles = [],
    plot_handles = fill(plot(), length(vars)), verbose = :low,
    kwargs...)
```

Plot history and forecast for `var` or `vars`. If these correspond to a
full-distribution forecast, you can specify the `bands_style` and `bands_pcts`.

### Inputs

- `m::AbstractModel`
- `var::Symbol` or `vars::Vector{Symbol}`: variable(s) to be plotted,
  e.g. `:obs_gdp` or `[:obs_gdp, :obs_nominalrate]`
- `class::Symbol`
- `input_type::Symbol`
- `cond_type::Symbol`

### Keyword Arguments

- `forecast_string::String`
- `bdd_and_unbdd::Bool`: if true, then unbounded means and bounded bands are plotted
- `untrans::Bool`: whether to plot untransformed (model units) history and forecast
- `fourquarter::Bool`: whether to plot four-quarter history and forecast
- `plotroot::String`: if nonempty, plots will be saved in that directory
- `title::String` or `titles::Vector{String}`
- `plot_handle::Plot` or `plot_handles::Vector{Plot}`: existing plot(s) on which
  to overlay new forecast plot(s)
- `verbose::Symbol`

See `?histforecast` for additional keyword arguments, all of which can be passed
into `plot_history_and_forecast`.

### Output

- `p::Plot` or `plots::OrderedDict{Symbol, Plot}`
"""
function plot_history_and_forecast(m::AbstractModel, var::Symbol, class::Symbol,
                                   input_type::Symbol, cond_type::Symbol;
                                   title::String = "", plot_handle::Plots.Plot = plot(),
                                   kwargs...)

    plots = plot_history_and_forecast(m, [var], class, input_type, cond_type;
                                      titles = isempty(title) ? String[] : [title],
                                      plot_handles = Plots.Plot[plot_handle],
                                      kwargs...)
    return plots[var]
end

function plot_history_and_forecast(m::AbstractModel, vars::Vector{Symbol}, class::Symbol,
                                   input_type::Symbol, cond_type::Symbol;
                                   forecast_string::String = "",
                                   bdd_and_unbdd::Bool = false,
                                   untrans::Bool = false,
                                   fourquarter::Bool = false,
                                   plotroot::String = figurespath(m, "forecast"),
                                   titles::Vector{String} = String[],
                                   plot_handles::Vector{Plots.Plot} = Plots.Plot[plot() for i = 1:length(vars)],
                                   verbose::Symbol = :low,
                                   kwargs...)
    # Determine output_vars
    if untrans && fourquarter
        error("Only one of untrans or fourquarter can be true")
    elseif untrans
        hist_prod  = :histut
        fcast_prod = :forecastut
    elseif fourquarter
        hist_prod  = :hist4q
        fcast_prod = :forecast4q
    else
        hist_prod  = :hist
        fcast_prod = :forecast
    end

    # Read in MeansBands
    hist  = read_mb(m, input_type, cond_type, Symbol(hist_prod, class), forecast_string = forecast_string)
    fcast = read_mb(m, input_type, cond_type, Symbol(fcast_prod, class), forecast_string = forecast_string,
                    bdd_and_unbdd = bdd_and_unbdd)

    # Get titles if not provided
    if isempty(titles)
        detexify_title = typeof(Plots.backend()) == Plots.GRBackend
        titles = map(var -> describe_series(m, var, class, detexify = detexify_title), vars)
    end

    # Loop through variables
    plots = OrderedDict{Symbol, Plots.Plot}()
    for (var, title, plot_handle) in zip(vars, titles, plot_handles)
        # Call recipe
        plots[var] = plot(plot_handle)
        histforecast!(var, hist, fcast;
                      ylabel = series_ylabel(m, var, class, untrans = untrans,
                                             fourquarter = fourquarter),
                      title = title, kwargs...)
        # Save plot
        if !isempty(plotroot)
            output_file = get_forecast_filename(plotroot, filestring_base(m), input_type, cond_type,
                                                Symbol(fcast_prod, "_", detexify(var)),
                                                forecast_string = forecast_string,
                                                fileformat = plot_extension())
            save_plot(plots[var], output_file, verbose = verbose)
        end
    end
    return plots
end

@userplot HistForecast

"""
```
histforecast(var, hist, forecast;
    start_date = hist.means[1, :date], end_date = forecast.means[end, :date],
    names = Dict{Symbol, String}(), colors = Dict{Symbol, Any}(),
    alphas = Dict{Symbol, Float64}(), styles = Dict{Symbol, Symbol}(),
    bands_pcts = union(which_density_bands(hist, uniquify = true),
                       which_density_bands(forecast, uniquify = true)),
    bands_style = :fan, label_bands = false, transparent_bands = true,
    tick_size = 2)
```

User recipe called by `plot_history_and_forecast`.

### Inputs

- `var::Symbol`: e.g. `obs_gdp`
- `hist::MeansBands`
- `forecast::MeansBands`

### Keyword Arguments

- `start_date::Date`
- `end_date::Date`
- `names::Dict{Symbol, String}`: maps keys `[:hist, :forecast, :bands]` to
  labels. If a key is missing from `names`, a default value will be used
- `colors::Dict{Symbol, Any}`: maps keys `[:hist, :forecast, :bands]` to
  colors
- `alphas::Dict{Symbol, Float64}`: maps keys `[:hist, :forecast, :bands]` to
  transparency values (between 0.0 and 1.0)
- `styles::Dict{Symbol, Symbol}`: maps keys `[:hist, :forecast, :bands]` to
  linestyles
- `bands_pcts::Vector{String}`: which bands percentiles to plot
- `bands_style::Symbol`: either `:fan` or `:line`
- `label_bands::Bool`
- `transparent_bands::Bool`
- `tick_size::Int`: x-axis (time) tick size in units of years

Additionally, all Plots attributes (see docs.juliaplots.org/latest/attributes)
are supported as keyword arguments.
"""
histforecast

@recipe function f(hf::HistForecast;
                   start_date = hf.args[2].means[1, :date],
                   end_date = hf.args[3].means[end, :date],
                   names = Dict{Symbol, String}(),
                   colors = Dict{Symbol, Any}(),
                   alphas = Dict{Symbol, Float64}(),
                   styles = Dict{Symbol, Symbol}(),
                   bands_pcts = union(which_density_bands(hf.args[2], uniquify = true),
                                      which_density_bands(hf.args[3], uniquify = true)),
                   bands_style = :fan,
                   label_bands = false,
                   transparent_bands = true,
                   tick_size = 2)
    # Error checking
    if length(hf.args) != 3 || typeof(hf.args[1]) != Symbol ||
        typeof(hf.args[2]) != MeansBands || typeof(hf.args[3]) != MeansBands

        error("histforecast must be given a Symbol and two MeansBands. Got $(typeof(hf.args))")
    end

    for dict in [names, colors, styles, alphas]
        bad_keys = setdiff(keys(dict), [:hist, :forecast, :bands])
        if !isempty(bad_keys)
            error("Invalid key(s) in $dict: $bad_keys")
        end
    end

    # Concatenate MeansBands
    var, hist, forecast = hf.args
    combined = cat(hist, forecast)
    dates = combined.means[:date]

    # Assign date ticks
    date_ticks = Base.filter(x -> start_date <= x <= end_date,    dates)
    date_ticks = Base.filter(x -> Dates.month(x) == 3,            date_ticks)
    date_ticks = Base.filter(x -> Dates.year(x) % tick_size == 0, date_ticks)
    xticks --> (map(Dates.value, date_ticks), map(Dates.year, date_ticks))

    # Bands
    sort!(bands_pcts, rev = true) # s.t. non-transparent bands will be plotted correctly
    inds = findall(start_date .<= combined.bands[var][:date] .<= end_date)

    for (i, pct) in enumerate(bands_pcts)
        seriestype := :line

        x = combined.bands[var][inds, :date]
        lb = combined.bands[var][inds, Symbol(pct, " LB")]
        ub = combined.bands[var][inds, Symbol(pct, " UB")]

        bands_color = haskey(colors, :bands) ? colors[:bands] : :blue
        bands_alpha = haskey(alphas, :bands) ? alphas[:bands] : 0.1
        bands_linestyle = haskey(styles, :bands) ? styles[:bands] : :solid

        if bands_style == :fan
            @series begin
                if transparent_bands
                    fillcolor := bands_color
                    fillalpha := bands_alpha
                else
                    if typeof(bands_color) in [Symbol, String]
                        bands_color = parse(Colorant, bands_color)
                    end
                    fillcolor := weighted_color_mean(bands_alpha*i, bands_color, colorant"white")
                    fillalpha := 1
                end
                linealpha  := 0
                fillrange  := ub
                label      := label_bands ? "$pct Bands" : ""
                x, lb
            end
        elseif bands_style == :line
            # Lower bound
            @series begin
                linewidth --> 2
                linecolor :=  bands_color
                linestyle :=  bands_linestyle
                label     :=  label_bands ? "$pct LB" : ""
                x, lb
            end

            # Upper bound
            @series begin
                linewidth --> 2
                linecolor :=  bands_color
                linestyle :=  bands_linestyle
                label     :=  label_bands ? "$pct UB" : ""
                x, ub
            end
        else
            error("bands_style must be either :fan or :line. Got $bands_style")
        end
    end

    # Mean history
    @series begin
        seriestype :=  :line
        linewidth  --> 2
        linecolor  :=  haskey(colors, :hist) ? colors[:hist] : :black
        alpha      :=  haskey(alphas, :hist) ? alphas[:hist] : 1.0
        linestyle  :=  haskey(styles, :hist) ? styles[:hist] : :solid
        label      :=  haskey(names, :hist) ? names[:hist] : "History"

        inds = intersect(findall(start_date .<= dates .<= end_date),
                         findall(hist.means[1, :date] .<= dates .<= hist.means[end, :date]))
        combined.means[inds, :date], combined.means[inds, var]
    end

    # Mean forecast
    @series begin
        seriestype :=  :line
        linewidth  --> 2
        linecolor  :=  haskey(colors, :forecast) ? colors[:forecast] : :red
        alpha      :=  haskey(alphas, :forecast) ? alphas[:forecast] : 1.0
        linestyle  :=  haskey(styles, :forecast) ? styles[:forecast] : :solid
        label      :=  haskey(names, :forecast) ? names[:forecast] : "Forecast"

        inds = intersect(findall(start_date .<= dates .<= end_date),
                         findall(hist.means[end, :date] .<= dates .<= forecast.means[end, :date]))
        combined.means[inds, :date], combined.means[inds, var]
    end
end