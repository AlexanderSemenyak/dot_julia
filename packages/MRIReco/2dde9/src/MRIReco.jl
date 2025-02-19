module MRIReco

#using Compat
using ImageMagick
if Sys.isapple()
  using QuartzImageIO
end
using FileIO
using ProgressMeter
using Reexport
@reexport using Images
using NFFT
using Distributions
using LinearOperators
using RegularizedLeastSquares
using StatsBase
using LinearAlgebra
using Random
@reexport using FFTW
using Distributed
using Graphics: @mustimplement
using ColorTypes
using ColorVectorSpace
using Wavelets
using HDF5
using LightXML
using NIfTI
@reexport using Unitful


include("Trajectories/Trajectories.jl")
include("Sequences/Sequence.jl")
include("Datatypes/Datatypes.jl")
include("Tools/Tools.jl")
include("Operators/Operators.jl")
include("Simulation/Simulation.jl")
include("Reconstruction/Reconstruction.jl")
include("IO/IO.jl")
include("Sampling/Sampling.jl")

end # module
