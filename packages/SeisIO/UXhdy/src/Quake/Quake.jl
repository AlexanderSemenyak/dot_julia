module Quake
using Blosc, Dates, DSP, LightXML, LinearAlgebra, Printf, SeisIO, Sockets
using HTTP: request, Messages.statustext
Blosc.set_compressor("lz4")
Blosc.set_num_threads(Sys.CPU_THREADS)
path = Base.source_dir()

const tracefields = (:az, :baz, :dist, :id, :loc, :fs, :gain, :misc, :name, :notes, :pha, :resp, :src, :t, :units, :x)


# imports
include("imports.jl")

# types for earthquake data
include("Types/EQLoc.jl")
include("Types/EQMag.jl")
include("Types/SourceTime.jl")
include("Types/SeisSrc.jl")
include("Types/SeisPha.jl")
include("Types/PhaseCat.jl")
include("Types/SeisHdr.jl")
include("Types/EventTraceData.jl")
include("Types/EventChannel.jl")
include("Types/SeisEvent.jl")

# extensions
for i in ls(path*"/Ext/*")
  if endswith(i, ".jl")
    include(i)
  end
end

# utilities
for i in ls(path*"/Utils/*")
  if endswith(i, ".jl")
    include(i)
  end
end

# web
for i in ls(path*"/Web/*")
  if endswith(i, ".jl")
    include(i)
  end
end

# exports
include("exports.jl")

end
