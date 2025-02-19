# Define MILP-R implementations of water distribution models.
export MILPRWaterModel, StandardMILPRForm

"AbstractMILPRForm is derived from AbstractWaterFormulation"
abstract type AbstractMILPRForm <: AbstractWaterFormulation end

"StandardMILPRForm is derived from AbstractMILPRForm"
abstract type StandardMILPRForm <: AbstractMILPRForm end

"The MILP-R model relaxes the head loss constraint to an inequality."
const MILPRWaterModel = GenericWaterModel{StandardMILPRForm}

"MILP-R constructor."
MILPRWaterModel(data::Dict{String, Any}; kwargs...) = GenericWaterModel(data, StandardMILPRForm; kwargs...)

function constraint_potential_loss(wm::GenericWaterModel{T}, a::Int, n::Int = wm.cnw) where T <: StandardMILPRForm
    # Outer-approximation cuts are iteratively added in the `solve_global` algorithm.
    if !haskey(wm.con[:nw][n], :potential_loss_1)
        wm.con[:nw][n][:potential_loss_1] = Dict{Int, Dict{Int, ConstraintRef}}()
        wm.con[:nw][n][:potential_loss_2] = Dict{Int, Dict{Int, ConstraintRef}}()
    end

    wm.con[:nw][n][:potential_loss_1][a] = Dict{Int, ConstraintRef}()
    wm.con[:nw][n][:potential_loss_2][a] = Dict{Int, ConstraintRef}()
end
