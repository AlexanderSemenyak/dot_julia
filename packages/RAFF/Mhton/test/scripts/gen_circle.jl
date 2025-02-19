# This script generates and draws examples for the circle detection

using PyPlot
using Printf
using DelimitedFiles
using RAFF

"""

Generate perturbed points in a circle given by `θSol`. Construct a
test file for `RAFF`.

"""
function gen_circle(np::Int, p::Int; std::Float64=0.1,
                    θSol::Vector{Float64}=10.0*randn(Float64, 3),
                    outTimes::Float64=5.0, interval::Vector{Float64}=rand(np)*2.0*π)

    ρ = (α, ρ) -> [ρ * cos(α) + θSol[1], ρ * sin(α) + θSol[2]]
    f = (x) -> (x[1] - θSol[1])^2 + (x[2] - θSol[2])^2 - θSol[3]^2

    data = Array{Float64, 2}(undef, np, 3) 

    # Points selected to be outliers
    v = RAFF.get_unique_random_points(np, np - p)

    for (i, α) in enumerate(interval)
    
        pt = ρ(α, θSol[3] + std * randn())

        if i in v

            pt = ρ(α, θSol[3] * (1 + outTimes * std * sign(randn())))

        end
        
        data[i, 1:2] = pt
        data[i,   3] = 0.0 #f(pt)

    end

    open("/tmp/output.txt", "w") do fp
    
        # Dimension of the domain of the function to fit
        @printf(fp, "%d\n", 2)

        for k = 1:np

            @printf(fp, "%20.15f %20.15f %20.15f %1d\n",
                    data[k, 1], data[k, 2], data[k, 3], Int(k in v))

        end

    end

    return data, v

end

function gen_ncircle(np::Int, p::Int; std::Float64=0.1,
                    θSol::Vector{Float64}=10.0*randn(Float64, 3),
                    outTimes::Float64=5.0, interval::Vector{Float64}=rand(p)*2.0*π)

    ρ = (α, ρ) -> [ρ * cos(α) + θSol[1], ρ * sin(α) + θSol[2]]
    f = (x) -> (x[1] - θSol[1])^2 + (x[2] - θSol[2])^2 - θSol[3]^2

    data = Array{Float64, 2}(undef, np, 3) 

    for (i, α) in enumerate(interval)
    
        pt = ρ(α, θSol[3] + std * randn())

        data[i, 1:2] = pt
        data[i,   3] = 0.0 #f(pt)

    end

    # Just random noise

    v = Vector{Int}(undef, np - p)
    
    for i = p + 1:np

        data[i, 1] = θSol[1] - 2.0 * θSol[3] + rand() * 4.0 * θSol[3]
        data[i, 2] = θSol[2] - 2.0 * θSol[3] + rand() * 4.0 * θSol[3]
        data[i, 3] = 1.0

        v[i - p] = i

    end

    open("/tmp/output.txt", "w") do fp
    
        # Dimension of the domain of the function to fit
        @printf(fp, "%d\n", 2)

        for k = 1:np

            @printf(fp, "%20.15f %20.15f %20.15f %1d\n",
                    data[k, 1], data[k, 2], data[k, 3], Int(k in v))

        end

    end

    return data, v

end


"""

Draw the points generated by the previous function.

"""
function draw_circle(data, outliers)

    np, = size(data)
    
    c = zeros(np)
    
    c[outliers] .= 1.0
    
    PyPlot.scatter(data[:, 1], data[:, 2], c=c, marker="o", s=50.0, linewidths=0.2,
                   cmap=PyPlot.cm["Paired"], alpha=0.9)
    
    PyPlot.axis("scaled")

    PyPlot.xticks([])

    PyPlot.yticks([])

    PyPlot.savefig("/tmp/circle.png", dpi=72)

end

"""

Draw the points and the solutions obtained. Save the picture in a file.

"""
function draw_circle_sol(tSol, fSol, lsSol)

    datafile = "/tmp/output.txt"

    fp = open(datafile, "r")

    N = parse(Int, readline(fp))

    M = readdlm(fp)

    close(fp)

    x  = M[:, 1]
    y  = M[:, 2]
    ρ  = M[:, 3]
    co = M[:, 4]

    t = [0:0.1:2.1 * π;]
    
    ptx = (α, ρ, d) -> ρ * cos(α) + d[1]
    pty = (α, ρ, d) -> ρ * sin(α) + d[2]

    # True solution
    
    pptx = (α) -> ptx(α, tSol[3], tSol[1:2])
    ppty = (α) -> pty(α, tSol[3], tSol[1:2])

    PyPlot.plot(pptx.(t), ppty.(t), "b--", label="True solution")
    
    # RAFF solution
    
    pptx = (α) -> ptx(α, fSol[3], fSol[1:2])
    ppty = (α) -> pty(α, fSol[3], fSol[1:2])

    PyPlot.plot(pptx.(t), ppty.(t), "g-", label="RAFF")
    
    # # LS solution
    
    # pptx = (α) -> ptx(α, lsSol[3], lsSol[1:2])
    # ppty = (α) -> pty(α, lsSol[3], lsSol[1:2])

    # PyPlot.plot(pptx.(t), ppty.(t), "r-", label="Least squares")

    PyPlot.scatter(x[co .== 0.0], y[co .== 0.0], color=PyPlot.cm."Pastel1"(2.0/9.0),
                   marker="o", s=50.0, linewidths=0.2)

    PyPlot.scatter(x[co .!= 0.0], y[co .!= 0.0], color=PyPlot.cm."Pastel1"(1.0/9.0),
                   marker=".", s=25.0, linewidths=0.2, label="Outliers")

    PyPlot.legend(loc=4)
    
    PyPlot.axis("scaled")

    PyPlot.xticks([])

    PyPlot.yticks([])

    PyPlot.savefig("/tmp/circle.png", dpi=150, bbox_inches="tight")

end
