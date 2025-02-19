function print_header_1()
    println("======================================================================")
    println("          ProxSDP : Proximal Semidefinite Programming Solver          ")
    println("                 (c) Mario Souto and Joaquim D. Garcia, 2018          ")
    println("                                                      v0.1.0          ")
    println("----------------------------------------------------------------------")
end

function print_parameters(opt::Options, conic_sets::ConicSets)
    println(" Solver parameters:")
    if length(conic_sets.socone) >= 1 && length(conic_sets.sdpcone) >= 1
        println("  tol_primal $(opt.tol_primal) tol_dual $(opt.tol_dual) tol_soc $(opt.tol_soc) tol_psd $(opt.tol_psd) ")
    elseif length(conic_sets.socone) >= 1
        println("  tol_primal $(opt.tol_primal) tol_dual $(opt.tol_dual) tol_soc $(opt.tol_soc)")
    elseif length(conic_sets.sdpcone) >= 1
        println("  tol_primal $(opt.tol_primal) tol_dual $(opt.tol_dual) tol_psd $(opt.tol_psd) ")
    else
        println("  tol_primal $(opt.tol_primal) tol_dual $(opt.tol_dual) ")
    end
    println("  max_iter $(opt.max_iter) max_beta $(opt.max_beta) min_beta $(opt.min_beta)")

    return nothing
end

function print_constraints(aff::AffineSets)
    println(" Constraints:")
    if aff.p >= 1 && aff.m >= 1
        println("  $(aff.p) linear equalities and $(aff.m) linear inequalities")
    elseif aff.p == 1 && aff.m >= 1
        println("  $(aff.p) linear equality and $(aff.m) linear inequalities")
    elseif aff.p >= 1 && aff.m == 1
        println("  $(aff.p) linear equalities and $(aff.m) linear inequality")
    elseif aff.p == 1
        println("  $(aff.p) linear equality ")
    elseif aff.p >= 1
        println("  $(aff.p) linear equalities ")
    elseif aff.m == 1
        println("  $(aff.m) linear inequality ")
    else
        println("  $(aff.m) linear inequalities ")
    end

    return nothing
end

function print_prob_data(conic_sets::ConicSets)
    soc_dict = Dict()
    for soc in conic_sets.socone
        if soc.len in keys(soc_dict)
            soc_dict[soc.len] += 1
        else
            soc_dict[soc.len] = 1
        end
    end
    psd_dict = Dict()
    for psd in conic_sets.sdpcone
        if psd.sq_side in keys(psd_dict)
            psd_dict[psd.sq_side] += 1
        else
            psd_dict[psd.sq_side] = 1
        end
    end 
    println(" Cones:")
    if length(conic_sets.socone) > 0
        for (k, v) in soc_dict
            if v == 1
                println("  1 second order cone of size $k")
            else
                println("  $v second order cones of size $k")
            end
        end
    end
    if length(conic_sets.sdpcone) > 0
        for (k, v) in psd_dict
            if v == 1
                println("  1 psd cone of size $(k)x$(k)")
            else
                println("  $v psd cones of size $(k)x$(k)")
            end
        end
    end

    return nothing
end

function print_header_2()
    println("----------------------------------------------------------------------")
    println(" Initializing Primal-Dual Hybrid Gradient method                      ")
    println("----------------------------------------------------------------------")
    println("|  iter  | comb. res | prim. res |  dual res |  max rank |  time (s) |")
    println("----------------------------------------------------------------------")

    return nothing
end

function print_progress(primal_res::Float64, dual_res::Float64, p::Params)
    s_k = @sprintf("%d", p.iter)
    s_k *= " |"
    s_s = @sprintf("%.4f", primal_res + dual_res)
    s_s *= " |"
    s_p = @sprintf("%.4f", primal_res)
    s_p *= " |"
    s_d = @sprintf("%.4f", dual_res)
    s_d *= " |"
    s_target_rank = @sprintf("%.0f", sum(p.target_rank))
    s_target_rank *= " |"
    s_time = @sprintf("%.4f", time() - p.time0)
    s_time *= " |"
    a = "|"
    a *= " "^max(0, 9 - length(s_k))
    a *= s_k
    a *= " "^max(0, 12 - length(s_s))
    a *= s_s
    a *= " "^max(0, 12 - length(s_p))
    a *= s_p
    a *= " "^max(0, 12 - length(s_d))
    a *= s_d
    a *= " "^max(0, 12 - length(s_target_rank))
    a *= s_target_rank
    a *= " "^max(0, 12 - length(s_time))
    a *= s_time
    println(a)

    return nothing
end

function print_result(stop_reason::Int, time_::Float64, prim_obj::Float64, dual_obj::Float64, gap::Float64, equa_feasibility::Float64, ineq_feasibility::Float64)
    println("----------------------------------------------------------------------")
    println(" Solver status:")
    if stop_reason == 1
        println("  Optimal solution found in $(round(time_; digits = 2)) seconds")
    elseif stop_reason == 2
        println("  ProxSDP failed to converge in $(round(time_; digits = 2)) seconds, time_limit reached")
    elseif stop_reason == 3
        println("  ProxSDP failed to converge in $(round(time_; digits = 2)) seconds, max_iter reached")
    end
    println("  Primal objective = $(round(prim_obj; digits = 5))")
    println("  Dual objective = $(round(dual_obj; digits = 5))")
    println("  Duality gap (%) = $(round(gap; digits = 2)) %")
    println("----------------------------------------------------------------------")
    println(" Primal feasibility:")
    println("  ||A(X) - b|| / (1 + ||b||) = $(round(equa_feasibility; digits = 6))    [linear equalities] ")
    println("  ||max(G(X) - h, 0)|| / (1 + ||h||) = $(round(ineq_feasibility; digits = 6))    [linear inequalities]")
    println("======================================================================")

    return nothing
end