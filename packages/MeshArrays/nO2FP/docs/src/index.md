# MeshArrays.jl documentation

`MeshArrays.jl` is a `Julia` package. It defines an Array type for collections of inter-connected arrays, and extends standard methods to readily operate on these `MeshArray`s. Its `exchange` methods transfer data between connected subdomains of the overall mesh. The internals of a `MeshArray` instance are regulated by index ranges, array sizes, and inter-connections that are encoded as a `gcmgrid` struct.

Such computational frameworks are commonly used in Earth System Modeling. `MeshArrays.jl` aims to provide a simple but versatile and powerful solution to this end. It was first introduced in this [JuliaCon-2018 presentation](https://youtu.be/RDxAy_zSUvg) as `gcmfaces.jl` (see [this other repo](https://github.com/gaelforget/JuliaCon2018Notebooks.git) for notebooks).

_Contents:_

```@contents
Pages = ["index.md","main.md","detail.md","API.md"]
Depth = 3
```

!!! note

    `MeshArrays.jl` is registered, documented, archived, and routinely tested, but also still regarded as a **preliminary implementation**.

## Install & Test

```
using Pkg
Pkg.add("MeshArrays")
Pkg.test("MeshArrays")
```

`Julia`'s package manager is documented [here within docs.julialang.org](https://docs.julialang.org/en/stable/stdlib/Pkg/).

## Use Examples

```
using MeshArrays
GridVariables=GCMGridOnes("cs",6,100)
(Rini,Rend,DXCsm,DYCsm)= MeshArrays.demo2(GridVariables);
```

The above will run an application which integrates lateral diffusion over a simplified global grid generated by `GCMGridOnes`. Alternatively,

```
git clone https://github.com/gaelforget/GRID_LLC90
GridVariables=GCMGridLoad(GCMGridSpec("LLC90"))
```

would download and use a pre-defined [global ocean grid](http://www.geosci-model-dev.net/8/3071/2015/), from the [MITgcm](https://mitgcm.readthedocs.io/en/latest/) community, to run the same example with a proper representation of scale factors and continents. For directions to plot results, see the help section of `demo2` (`?MeshArrays.demo2`).
