export set_raff_output_level, set_lm_output_level

"""

    check_ftrusted(ftrusted::Union{Float64, Tuple{Float64, Float64}}, np::Int)

Utility function to check `ftrusted` parameter in [`raff`](@ref) and
[`praff`](@ref). Throws an `ErrorException` if the percentage of
trusted points is incorrect.

"""
function check_ftrusted(ftrusted::Union{Float64, Tuple{Float64, Float64}}, np::Int)

    if typeof(ftrusted) == Float64

        (!(0.0 <= ftrusted <= 1.0)) && error("Bad value for `ftrusted`: $(ftrusted).")

        return Int(round(ftrusted * np)), np

    end

    (!(0.0 <= ftrusted[1] <= ftrusted[2] <= 1.0)) &&
        error("Bad interval for `ftrusted`: $(ftrusted[1]) > $(ftrusted[2]).")

    return Int(round(ftrusted[1] * np)), Int(round(ftrusted[2] * np))

end    

"""

    eliminate_local_min!(sols::Vector{RAFFOutput})

Check if the function value of the solution found by smaller values of
`p` is not greater when compared with larger ones. This certainly
indicates that a local minimizer was found by the smaller `p`.

"""
function eliminate_local_min!(model::Function, data::Array{Float64, 2},
                              sols::Vector{RAFFOutput})

    lv = length(sols)

    sec_sol_ind = -1

    # Start from the largest p
    for i = lv:-1:1

        (sols[i].status != 1) && continue
        
        for j = i - 1:-1:1

            if (sols[j].status == 1) && (sols[j].f > sols[i].f)

                @debug("  Possible local minimizer for p = $(sols[j].p) " *
                       "with f = $(sols[j].f). Removing it.")
                
                sols[j] = RAFFOutput(0)

            end

        end

    end

    # Test the maximum 'p'

    nump, = size(data)
    
    maxp = sols[lv]
        
    if (lv > 1) && (maxp.status == 1)

        i = lv - 1

        # while (i > 0) && (sols[i].status != 1)

        #     i -= 1

        # end

        bestf = maxp.f
        j = 0
        
        while (i > 0)

            if  (sols[i].status == 1) && (sols[i].f < bestf)

                bestf = sols[i].f

                j = i

            end

            i -= 1

        end

        if j == 0
            
            @debug("  Nobody to reject p = $(maxp.p).")

        else

            sec_sol = sols[j]
            
            @debug("  p = $(sec_sol.p) will try to reject p = $(maxp.p).")

            nmin = 0

            for i = 1:nump

                y  = data[i, end]
                x  = @view data[i, 1:(end - 1)]
                y1 = model(x, maxp.solution)
                y2 = model(x, sec_sol.solution)
                
                (abs(y - y1) < abs(y - y2)) && (nmin += 1)

            end

            if nmin < lv / 2

                @debug("  nmin = $(nmin). Rejecting p = $(maxp.p).")

                sols[lv] = RAFFOutput(0)

            end

        end
        
    end
    
end


"""

This function is an auxiliary function. It finds the `p` smallest
values of vector `V` and brings them to the first `p` positions. The
indexes associated with the `p` smallest values are stored in `ind`.

"""
function sort_fun!(V::Vector{Float64}, ind::Vector{Int}, p::Int)

    # If p is invalid, returns an empty view
    (p <= 0) && (return @view(ind[1:p]), @view(V[1:p]))
    
    npun = length(ind)
    
    for i = 1:npun
        ind[i] = i
    end
    
    for i = 1:p
        
        for j = i + 1:npun
            
            if V[i] > V[j]
                
                aux = ind[j]
                ind[j] = ind[i]
                ind[i] = aux
                
                vaux = V[j]
                V[j] = V[i]
                V[i] = vaux
            end
        end
    end

    return @view(ind[1:p]), @view(V[1:p])
    
end

"""

    set_raff_output_level(level::LogLevel)

Set the output level of [`raff`](@ref) and [`praff`](@ref) algorithms
to the desired logging level. Options are (from highly verbose to just
errors): `Logging.Debug`, `Logging.Info`, `Logging.Warn` and
`Logging.Error`. The package
[`Logging`](https://docs.julialang.org/en/v1.0/stdlib/Logging/index.html)
needs to be loaded.

Defaults to `Logging.Error`.

"""
function set_raff_output_level(level::LogLevel)

    global raff_logger = ConsoleLogger(stdout, level)

end

"""

    set_lm_output_level(level::LogLevel)

Set the output level of [`lmlovo`](@ref) algorithm to the desired
logging level. Options are (from highly verbose to just errors):
`Logging.Debug`, `Logging.Info`, `Logging.Warn` and
`Logging.Error`. The package
[`Logging`](https://docs.julialang.org/en/v1.0/stdlib/Logging/index.html)
needs to be loaded.

Defaults to `Logging.Error`.

"""
function set_lm_output_level(level::LogLevel)

    global lm_logger = ConsoleLogger(stdout, level)

end
