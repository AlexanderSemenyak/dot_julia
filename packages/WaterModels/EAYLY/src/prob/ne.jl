export run_ne_hw, post_ne_hw

function run_ne_hw(file, model_constructor, solver; kwargs...)
    return run_generic_model(file, model_constructor, solver, post_ne_hw; kwargs...)
end

function run_ne_hw(file, modifications_path, model_constructor, solver; kwargs...)
    return run_generic_model(file, modifications_path, model_constructor, solver, post_ne_hw; kwargs...)
end

function post_ne_hw(wm::GenericWaterModel, n_n::Int = wm.cnw; kwargs...)
    variable_head(wm, n_n)
    variable_directed_flow(wm, n_n)

    variable_head_difference(wm, n_n)
    variable_flow_direction(wm, n_n)
    variable_resistance(wm, n_n)

    for a in collect(ids(wm, :connection))
        constraint_select_resistance(wm, a, n_n)
        constraint_select_flow_term(wm, a, n_n)
        constraint_head_difference(wm, a, n_n)
        constraint_potential_loss(wm, a, n_n)
        constraint_potential_loss_slope(wm, a, n_n)
    end

    for i in collect(ids(wm, :reservoirs))
        constraint_source_flow(wm, i)
    end

    for (i, junction) in wm.ref[:nw][wm.cnw][:junctions]
        constraint_directed_flow_conservation(wm, i, n_n)

        if junction["demand"] > 0.0
            constraint_sink_flow(wm, i)
        end
    end

    objective_minimize_resistance_cost(wm)
end
