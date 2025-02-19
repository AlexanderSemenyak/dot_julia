using WaterModels
using GLPK
using GLPKMathProgInterface
using InfrastructureModels
using Ipopt
using JuMP
using Memento
using Pavito
using Test

# Suppress warnings during testing.
setlevel!(getlogger(InfrastructureModels), "error")
setlevel!(getlogger(WaterModels), "error")

# Solver setup.
glpk = GLPKSolverMIP(presolve = false, msg_lev = GLPK.MSG_OFF)
ipopt = IpoptSolver(print_level = 0, tol = 1.0e-9, max_iter=9999)
pavito = PavitoSolver(cont_solver = ipopt, mip_solver = glpk)

# Perform the tests.
@testset "WaterModels" begin
    include("io.jl")
    include("hw.jl")
end
