<!-- # OMEinsum -->
<div align="center"> <img
src="ome-logo.png"
alt="OMEinsum logo" width="510"></img>
<h1>OMEinsum - One More Einsum</h1>
</div>

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://under-Peter.github.io/OMEinsum.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://under-Peter.github.io/OMEinsum.jl/dev)
[![Build Status](https://travis-ci.com/under-Peter/OMEinsum.jl.svg?branch=master)](https://travis-ci.com/under-Peter/OMEinsum.jl)
[![pipeline status](https://gitlab.com/JuliaGPU/OMEinsum-jl/badges/master/pipeline.svg)](https://gitlab.com/user/JuliaGPU/OMEinsum-jl/master)
[![Codecov](https://codecov.io/gh/under-Peter/OMEinsum.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/under-Peter/OMEinsum.jl)

This is a repository for the _Google Summer of Code_ project on *Differentiable Tensor Networks*.
It implements one function that both computer scientists and physicists love, the *Einstein summation*

<img alt="einsum definition" src="https://github.com/under-Peter/OMEinsum.jl/blob/master/docs/einsum_define.png?raw=true" width=300/>

To find out the details about einsum, please check out my [nextjournal-article](https://nextjournal.com/under-Peter/julia-summer-of-einsum) or the [numpy-manual](https://docs.scipy.org/doc/numpy/reference/generated/numpy.einsum.html).

Einstein summation can be implemented in no more than 20 lines of Julia code, the automatic differentiation is also [straightforward](https://giggleliu.github.io/2019/04/02/einsumbp.html). The main effort of this package is improving the [performance](https://github.com/under-Peter/OMEinsum-Benchmarks) utilizing Julia [multiple dispatch on traits](https://white.ucc.asn.au/2018/10/03/Dispatch,-Traits-and-Metaprogramming-Over-Reflection.html). So that people can enjoy the speed of faster specific implementations like BLAS functions, `sum` and `permutedims` on both CPU and GPU without suffering from runtime overhead.

*Note: why the test coverage is not 100%* - GPU-code coverage is not evaluated although we test the GPU code properly on gitlab. Ignoring the GPU-code, the actual coverage is at about _97%_.

## Install

To install, type `]` in a julia REPL and then input
```julia pkg
pkg> add OMEinsum
```

## Learn by Examples
To avoid runtime overhead, we recommend users to use [non-standard string literal](https://docs.julialang.org/en/v1/manual/metaprogramming/#Non-Standard-String-Literals-1) `@ein_str`.
For example
```julia
julia> a, b = rand(2,2), rand(2,2);

julia> ein"ik,kj -> ij"(a,b) # multiply two matrices `a` and `b`

julia> ein"ij -> "(a)[] # sum a matrix, `[]` is used to index the output 0-dimensional array

julia> ein"->ii"(asarray(1), size_info=IndexSize('i'=>5)) # get 5 x 5 identity matrix
```

Alternatively, people can specify the contraction with a construction approach
```julia
julia> einsum(EinCode((('i','k'),('k','j')),('i','j')),(a,b))
```
or a macro based interface, `@ein` macro,
which is closer to the standard way of writing einsum-operations in physics
```julia
julia> @ein c[i,j] := a[i,k] * b[k,j];
```

#### A table for reference
| code             | meaning         |
| ---------------- | --------------- |
| `ein"ij,jk->ik"`   | matrix matrix multiplication |
| `ein"ijl,jkl->ikl"`   | batched - matrix matrix multiplication |
| `ein"ij,j->i"`   | matrix vector multiplication |
| `ein"ij,ik,il->jkl"`   | star contraction |
| `ein"ii->"`   | trace |
| `ein"ij->i"` | sum |
| `ein"ii->i"` | take the diagonal part of a matrix |
| `ein"ijkl->ilkj"` | permute the dimensions of a tensor |
| `ein"i->ii"` | construct a diagonal matrix |
| `ein"->ii"`  | broadcast a scalar to the diagonal part of a matrix |
| `ein"ij,ij->ij"`  | element wise product |
| `ein"ij,kl->ijkl"`  | outer product |


To see more examples using the GPU and autodiff, check out our asciinema-demo here:
[![asciicast](https://asciinema.org/a/wE4CtIzWUC3R0GkVV28rVBRFb.svg)](https://asciinema.org/a/wE4CtIzWUC3R0GkVV28rVBRFb)

## Application

For an application in tensor network algorithms, check out the [TensorNetworkAD](https://github.com/under-Peter/TensorNetworkAD.jl)
package, where `OMEinsum` is used to evaluate tensor-contractions, permutations and summations.

#### Toy Application: solving a 3-coloring problem on the Petersen graph
Let us focus on graphs
with vertices with three edges each. A question one might ask is:
How many different ways are there to colour the edges of the graph with
three different colours such that no vertex has a duplicate colour on its edges?

The counting problem can be transformed into a contraction of rank-3 tensors
representing the edges. Consider the tensor `s` defined as
```julia
julia> s = map(x->Int(length(unique(x.I)) == 3), CartesianIndices((3,3,3)))
```

Then we can simply contract `s` tensors to get the number of 3 colourings satisfying the above condition!
E.g. for two vertices, we get 6 distinct colourings:
```julia
julia> ein"ijk,ijk->"(s,s)[]
6
```

Using that method, it's easy to find that e.g. the peterson graph allows no 3 colouring, since
```julia
julia> ein"afl,bhn,cjf,dlh,enj,ago,big,cki,dmk,eom->"(fill(s, 10)...)[]
0
```

The peterson graph consists of 10 vertices and 15 edges and looks like a pentagram
embedded in a pentagon as depicted here:

![](https://upload.wikimedia.org/wikipedia/commons/thumb/f/f5/Petersen_graph.svg/252px-Petersen_graph.svg.png)

Confronted with the above result, we can ask whether the peterson graph allows a relaxed variation of 3 colouring, having one vertex that might accept duplicate colours. The answer to that can be found using the gradient w.r.t a vertex:
```julia
julia> using Zygote: gradient

julia> gradient(x->ein"afl,bhn,cjf,dlh,enj,ago,big,cki,dmk,eom->"(x,s,s,s,s,s,s,s,s,s)[], s)[1] |> sum
0
```
This tells us that even if we allow duplicates on one vertex, there are no 3-colourings for the peterson graph.

## Contribute

Suggestions and Comments in the _Issues_ are welcome.

## License
MIT License
