struct NDBasis{T,M} <: Space{T}
    geo::M
    fns::Vector{Vector{Shape{T}}}
end

refspace(s::NDBasis) = NDRefSpace{scalartype(s)}()


function nedelec(surface, edges)

    T = coordtype(surface)
    num_edges = numcells(edges)

    C = connectivity(edges, surface, identity)
    rows = rowvals(C)
    vals = nonzeros(C)

    fns = Vector{Vector{Shape{T}}}(undef,num_edges)
    for (i,edge) in enumerate(cells(edges))

        fns[i] = Vector{Shape{T}}()

        for k in nzrange(C,i)

            j = rows[k] # j is the index of a cell adjacent to edge
            s = vals[k] # s contains the oriented (signed) local index of edge[i] in cell[j]

            i == 3 && @show s
            push!(fns[i], Shape{T}(j, abs(s), sign(s)))
        end
    end

    NDBasis(surface, fns)
end
