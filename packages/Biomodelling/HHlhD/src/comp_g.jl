function comp_g(data)

# Compute the auxiliary functions h. For details see "Efficient step size()
# selection for the tau-leaping simulation method" of Cao, Gillespie and
# Petzold.

#  ---- INPUT PARAMETERS ----
#   data: same structure as in "reaction_tauleap.m", [1x1]
#   data.hor : highest order of reaction, [Nx1]
#   data.mrr : maximum required reactants, [Nx1]

# ---- OUTPUT PARAMETERS ----
#   g : auxiliary function (as a vector), [Nx1]


    hor = data.hor
    mrr = data.mrr

    g = zeros(data.N, 1)

    for i = 2:data.N
    # compute g
        if mrr[i] == 1
            g[i] = hor[i]
        
        elseif mrr[i] == 2
            g[i] = hor[i] * (1 + 1 / (2 * (data.X[i] - 1)))
        
        elseif mrr[i] == 3
            g[i] = hor[i] * (1 + 1 / (3 * (data.X[i] - 1)) + 2 / (3 * (data.X[i] - 2)))
        
        else
            g[i] = hor[i]; # this is an approximation valid only when mrr==1.
        end
    end
    return g
end
