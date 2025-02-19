
"""
Define your model to be a subtype of `AbstractModel`. Your model has to have the following fields, but can also have other fields of your choice.

e.g.

```
mutable struct MyModel <: AbstractModel
  scheduler::Function
  space
  agents::Array{Integer}  # a list of agents ids
end
```

`scheduler` can be one of the default functions (`random_activation`), or your own function.
"""
abstract type AbstractModel end

"""
  nagents(model::AbstractModel)

Returns the number of agents.
"""
nagents(model::AbstractModel) = length(model.agents)

function dummystep(a::AbstractAgent, b::AbstractModel)
end

"""
    kill_agent!(agent::AbstractAgent, model::AbstractModel)

Removes an agent from the list of agents and from the space.
"""
function kill_agent!(agent::AbstractAgent, model::AbstractModel)
  if typeof(agent.pos) <: Tuple
    agentnode = coord_to_vertex(agent.pos, model)
  else
    agentnode = agent.pos
  end
  splice!(model.space.agent_positions[agentnode], findfirst(a->a==agent.id, model.space.agent_positions[agentnode]))  # remove from the grid
  splice!(model.agents, findfirst(a->a==agent, model.agents))  # remove from the model.agents
end

"""
    step!(agent_step::Function, model::AbstractModel)

Updates agents one step. Agents will be updated as specified by the `model.scheduler`.
"""
function step!(agent_step, model::AbstractModel)
  activation_order = return_activation_order(model)
  for index in activation_order
    agent_step(model.agents[index], model)
  end
end

"""
    step!(agent_step::Function, model::AbstractModel, nsteps::Integer)

Repeats the `step` function `nsteps` times without collecting data.
"""
function step!(agent_step, model::AbstractModel, nsteps::Integer)
  for i in 1:nsteps
    step!(agent_step, model)
  end
end

"""
    step!(agent_step::Function, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, steps_to_collect_data::Array{Int64})

Repeats the `step` function `nsteps` times, and collects all agent fields in `agent_properties` at steps `steps_to_collect_data`.

"""
function step!(agent_step::Function, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, steps_to_collect_data::Array{Int64})

  # Run the first step of the model to fill in the dataframe
  # step!(agent_step, model)
  df = data_collector(agent_properties, steps_to_collect_data, model, 1)

  for ss in 2:nsteps
    step!(agent_step, model)
    # collect data
    if ss in steps_to_collect_data
      df = data_collector(agent_properties, steps_to_collect_data, model, ss, df)
    end
  end
  # if 1 is not in `steps_to_collect_data`, remove the first row.
  if !in(1, steps_to_collect_data)
    df = df[2:end, :]
  end
  return df
end

"""
    step!(agent_step::Function, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, aggregators::Array, steps_to_collect_data::Array{Integer})

Repeats the `step` function `nsteps` times, and applies functions in `aggregators` to values of agent fields in `agent_properties` at steps `steps_to_collect_data`.
"""
function step!(agent_step, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, aggregators::Array, steps_to_collect_data::Array{Int64})
  
  # Run the first step of the model to fill in the dataframe
  # step!(agent_step, model)
  df = data_collector(agent_properties, aggregators, steps_to_collect_data, model, 1)

  for ss in 2:nsteps
    step!(agent_step, model)
    # collect data
    if ss in steps_to_collect_data
      df = data_collector(agent_properties, aggregators, steps_to_collect_data, model, ss, df)
    end
  end
  # if 1 is not in `steps_to_collect_data`, remove the first row.
  if !in(1, steps_to_collect_data)
    df = df[2:end, :]
  end
  return df
end

"""
    step!(agent_step::Function, model::AbstractModel, nsteps::Integer, propagg::Dict, steps_to_collect_data::Array{Integer})

Repeats the `step` function `nsteps` times, and applies functions in values of the `propagg` dict to its keys at steps `steps_to_collect_data`.
"""
function step!(agent_step, model::AbstractModel, nsteps::Integer, propagg::Dict, steps_to_collect_data::Array{Int64})
  
  # Run the first step of the model to fill in the dataframe
  # step!(agent_step, model)
  df = data_collector(propagg, steps_to_collect_data, model, 1)

  for ss in 2:nsteps
    step!(agent_step, model)
    # collect data
    if ss in steps_to_collect_data
      df = data_collector(propagg, steps_to_collect_data, model, ss, df)
    end
  end
  # if 1 is not in `steps_to_collect_data`, remove the first row.
  if !in(1, steps_to_collect_data)
    df = df[2:end, :]
  end
  return df
end


"""
    step!(agent_step::Function, model_step::Function, model::AbstractModel)

Updates agents one step without collecting data. This function accepts two functions, one for update agents and one for updating the whole model one after all the agents have been updated.
"""
function step!(agent_step, model_step, model::AbstractModel)
  activation_order = return_activation_order(model)
  for index in activation_order
    agent_step(model.agents[index], model)
  end
  model_step(model)
end

"""
    step!(agent_step::Function, model_step::Function, model::AbstractModel, nsteps::Integer)

Repeats the `step` function `nsteps` times without collecting data.
"""
function step!(agent_step, model_step, model::AbstractModel, nsteps::Integer)
  for ss in 1:nsteps
    step!(agent_step, model_step, model)
  end
end

"""
    step!(agent_step::Function, model_step::Function, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, steps_to_collect_data::Array{Integer})

Repeats the `step` function `nsteps` times, and collects all agent fields in `agent_properties` at steps `steps_to_collect_data`.
"""
function step!(agent_step, model_step, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, steps_to_collect_data::Array{Int64})

  # Run the first step of the model to fill in the dataframe
  # step!(agent_step, model_step, model)
  df = data_collector(agent_properties, steps_to_collect_data, model, 1)

  for ss in 2:nsteps
    step!(agent_step, model_step, model)
    # collect data
    if ss in steps_to_collect_data
      df = data_collector(agent_properties, steps_to_collect_data, model, ss, df)
    end
  end
  # if 1 is not in `steps_to_collect_data`, remove the first columns. TODO: remove ids that were only present in the first step
  if !in(1, steps_to_collect_data)
    first_col = length(agent_properties)+2 # 1 for id and 1 for passing these agent properties
    end_col = size(df, 2)
    df = df[:, vcat([1], collect(first_col:end_col))]
  end
  return df
end

"""
    step!(agent_step::Function, model_step::Function, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, aggregators::Array, steps_to_collect_data::Array{Integer})

Repeats the `step` function `nsteps` times, and applies functions in `aggregators` to values of agent fields in `agent_properties` at steps `steps_to_collect_data`.
"""
function step!(agent_step, model_step, model::AbstractModel, nsteps::Integer, agent_properties::Array{Symbol}, aggregators::Array, steps_to_collect_data::Array{Int64})
  
  # Run the first step of the model to fill in the dataframe
  # step!(agent_step, model_step, model)
  df = data_collector(agent_properties, aggregators, steps_to_collect_data, model, 1)

  for ss in 2:nsteps
    step!(agent_step, model_step, model)
    # collect data
    if ss in steps_to_collect_data
      df = data_collector(agent_properties, aggregators, steps_to_collect_data, model, ss, df)
    end
  end
  # if 1 is not in `steps_to_collect_data`, remove the first row.
  if !in(1, steps_to_collect_data)
    df = df[2:end, :]
  end
  return df
end

"""
    step!(agent_step::Function, model_step::Function, model::AbstractModel, nsteps::Integer, propagg::Dict, steps_to_collect_data::Array{Integer})

Repeats the `step` function `nsteps` times, and applies functions in values of the `propagg` dict to its keys at steps `steps_to_collect_data`.
"""
function step!(agent_step, model_step, model::AbstractModel, nsteps::Integer, propagg::Dict, steps_to_collect_data::Array{Int64})
  
  # Run the first step of the model to fill in the dataframe
  # step!(agent_step, model_step, model)
  df = data_collector(propagg, steps_to_collect_data, model, 1)

  for ss in 2:nsteps
    step!(agent_step, model_step, model)
    # collect data
    if ss in steps_to_collect_data
      df = data_collector(propagg, steps_to_collect_data, model, ss, df)
    end
  end
  # if 1 is not in `steps_to_collect_data`, remove the first row.
  if !in(1, steps_to_collect_data)
    df = df[2:end, :]
  end
  return df
end
