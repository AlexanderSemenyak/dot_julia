# Functions for working with the WaterModels internal data format.

function calc_head_bounds(wm::GenericWaterModel, n::Int = wm.cnw)
    # Get indices of nodes used in the network.
    junction_ids = collect(ids(wm, :junctions))
    reservoir_ids = collect(ids(wm, :reservoirs))
    nodes = [junction_ids; reservoir_ids]

    # Get placeholders for junctions and reservoirs.
    junctions = wm.ref[:nw][n][:junctions]
    reservoirs = wm.ref[:nw][n][:reservoirs]

    # Get maximum elevation/head values at nodes.
    max_elev = maximum([node["elev"] for node in values(junctions)])
    max_head = maximum([node["head"] for node in values(reservoirs)])

    # Initialize the dictionaries for minimum and maximum heads.
    head_min = Dict([(i, -Inf) for i in nodes])
    head_max = Dict([(i, Inf) for i in nodes])

    for (i, junction) in junctions
        # The minimum head at junctions must be above the initial elevation.
        if haskey(junction, "minimumHead")
            head_min[i] = max(junction["elev"], junction["minimumHead"])
        else
            head_min[i] = junction["elev"]
        end

        # The maximum head at junctions must be below the max reservoir height.
        if haskey(junction, "maximumHead")
            head_max[i] = max(max(max_elev, max_head), junction["maximumHead"])
        else
            head_max[i] = max(max_elev, max_head)
        end
    end

    for (i, reservoir) in reservoirs
        # Head values at reservoirs are fixed.
        head_min[i] = reservoir["head"]
        head_max[i] = reservoir["head"]
    end

    # Return the dictionaries of lower and upper bounds.
    return head_min, head_max
end

function calc_head_difference_bounds(wm::GenericWaterModel, n::Int = wm.cnw)
    # Get placeholders for junctions and reservoirs.
    connections = wm.ref[:nw][n][:connection]

    # Initialize the dictionaries for minimum and maximum head differences.
    head_lbs, head_ubs = calc_head_bounds(wm, n)
    head_diff_min = Dict([(a, -Inf) for a in keys(connections)])
    head_diff_max = Dict([(a, Inf) for a in keys(connections)])

    # Compute the head difference bounds.
    for (a, connection) in connections
        i = parse(Int, connection["node1"])
        j = parse(Int, connection["node2"])
        head_diff_min[a] = head_lbs[i] - head_ubs[j]
        head_diff_max[a] = head_ubs[i] - head_lbs[j]
    end

    # Return the head difference bound dictionaries.
    return head_diff_min, head_diff_max
end

function calc_directed_flow_upper_bounds(wm::GenericWaterModel, n::Int = wm.cnw, exponent::Float64 = 1.852)
    dh_lb, dh_ub = calc_head_difference_bounds(wm, n)

    connections = wm.ref[:nw][n][:connection]
    ub_n = Dict([(a, Float64[]) for a in keys(connections)])
    ub_p = Dict([(a, Float64[]) for a in keys(connections)])

    junctions = values(wm.ref[:nw][n][:junctions])
    sum_demand = sum(junction["demand"] for junction in junctions)

    for (a, connection) in connections
        L = connection["length"]
        R_a = wm.ref[:nw][n][:resistance][a]

        ub_n[a] = zeros(Float64, (length(R_a),))
        ub_p[a] = zeros(Float64, (length(R_a),))

        for r in 1:length(R_a)
            ub_n[a][r] = abs(dh_lb[a] / (L * R_a[r]))^(1.0 / exponent)
            ub_n[a][r] = min(ub_n[a][r], sum_demand)

            ub_p[a][r] = abs(dh_ub[a] / (L * R_a[r]))^(1.0 / exponent)
            ub_p[a][r] = min(ub_p[a][r], sum_demand)

            if connection["flow_direction"] == POSITIVE || dh_lb[a] >= 0.0
                ub_n[a][r] = 0.0
            elseif connection["flow_direction"] == NEGATIVE || dh_ub[a] <= 0.0
                ub_p[a][r] = 0.0
            end

            if haskey(connection, "diameters") && haskey(connection, "maximumVelocity")
                D_a = connection["diameters"][r]["diameter"]
                v_a = connection["maximumVelocity"]
                rate_bound = 0.25 * pi * v_a * D_a * D_a
                ub_n[a][r] = min(ub_n[a][r], rate_bound)
                ub_p[a][r] = min(ub_p[a][r], rate_bound)
            end
        end
    end

    return ub_n, ub_p
end

function get_node_ids(connection::Dict{String, Any})
    i = parse(Int, connection["node1"])
    j = parse(Int, connection["node2"])
    return i, j
end

function calc_resistances_hw(connections::Dict{Int, Any})
    resistances = Dict([(a, Array{Float64, 1}()) for a in keys(connections)])

    for (a, connection) in connections
        if haskey(connection, "resistances")
            resistances[a] = sort(connection["resistances"], rev = true)
        elseif haskey(connection, "resistance")
            resistance = connection["resistance"]
            resistances[a] = vcat(resistances[a], resistance)
        elseif haskey(connection, "diameters")
            for entry in connection["diameters"]
                diameter = entry["diameter"]
                roughness = connection["roughness"]
                r = 10.67 / (roughness^1.852 * diameter^4.87)
                resistances[a] = vcat(resistances[a], r)
            end

            resistances[a] = sort(resistances[a], rev = true)
        else
            diameter = connection["diameter"]
            roughness = connection["roughness"]
            r = 10.67 / (roughness^1.852 * diameter^4.87)
            resistances[a] = vcat(resistances[a], r)
        end
    end

    return resistances
end

function calc_resistance_costs_hw(connections::Dict{Int, Any})
    costs = Dict([(a, Array{Float64, 1}()) for a in keys(connections)])

    for (a, connection) in connections
        if haskey(connection, "diameters")
            resistances = Array{Float64, 1}()

            for entry in connection["diameters"]
                diameter = entry["diameter"]
                roughness = connection["roughness"]
                resistance = 10.67 / (roughness^1.852 * diameter^4.87)
                resistances = vcat(resistances, resistance)
                costs[a] = vcat(costs[a], entry["costPerUnitLength"])
            end

            sort_indices = sortperm(resistances, rev = true)
            costs[a] = costs[a][sort_indices]
        else
            costs[a] = vcat(costs[a], 0.0)
        end
    end

    return costs
end

function has_known_flow_direction(connection::Pair{Int, Any})
    return connection.second["flow_direction"] != UNKNOWN
end

function is_ne_pipe(connection::Pair{Int, Any})
    return haskey(connection.second, "diameters")
end

function is_out_node_function(i::Int)
    function is_out_node(connection::Pair{Int, Any})
        return parse(Int, connection.second["node1"]) == i
    end

    return is_out_node
end

function is_in_node_function(i::Int)
    function is_in_node(connection::Pair{Int, Any})
        return parse(Int, connection.second["node2"]) == i
    end

    return is_in_node
end
