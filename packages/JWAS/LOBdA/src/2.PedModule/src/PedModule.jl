module PedModule

using DataFrames,CSV
using SparseArrays
using ProgressMeter

export get_pedigree

"""
    get_pedigree(pedfile::AbstractString;header=false,separator=',')
* Get pedigree informtion from a pedigree file with **header** (defaulting to `false`)
  and **separator** (defaulting to `,`).
* Pedigree file format:

```
a,0,0
c,a,b
d,a,c
```
"""
function get_pedigree(pedfile::AbstractString;header=false,separator=',')
    printstyled("The delimiter in ",split(pedfile,['/','\\'])[end]," is \'",separator,"\'.\n",bold=false,color=:red)
    mkPed(pedfile,header=header,separator=separator)
end

mutable struct PedNode
    seqID::Int64
    sire::String
    dam::String
    f::Float64
end

mutable struct Pedigree
    currentID::Int64
    idMap::Dict{AbstractString,PedNode}
    aij::Dict{Int64, Float64}
    setNG::Set
    setG::Set
    setG_core::Set
    setG_notcore::Set
    #individuals IDs (in order of numerator relationship matrix A)
    IDs::Array{String,1}
end

function code!(ped::Pedigree,id::AbstractString)
# The idea for this function came from a perl script by Bernt Guldbrandtsen
    if ped.idMap[id].seqID!=0
        return
    end
    sireID = ped.idMap[id].sire
    damID  = ped.idMap[id].dam
    if sireID!="0" && ped.idMap[sireID].seqID==0
        code!(ped,sireID)
    end
    if damID!="0" && ped.idMap[damID].seqID==0
        code!(ped,damID)
    end
    ped.idMap[id].seqID = ped.currentID
    ped.currentID += 1
end

function fillMap!(ped::Pedigree,df)
    #Warning: indexing with colon as row will create a copy in the future
    #use df[col_inds] to get the columns without copying
    n = size(df,1)
    for i in df[2] #same to df[:,2] in deprecated CSV
        if i!="0" && !haskey(ped.idMap,i)          # skip 0 and if already done
            ped.idMap[i]=PedNode(0,"0","0",-1.0)
        end
    end
    for i in df[3]
        if i!="0" && !haskey(ped.idMap,i)         # make an entry for all dams
            ped.idMap[i]=PedNode(0,"0","0",-1.0)
        end
    end
    j=1
    for i in df[1]
        ped.idMap[i]=PedNode(0,df[j,2],df[j,3],-1.0)
        j+=1
    end
end

function calcAddRel!(ped::Pedigree,id1::AbstractString,id2::AbstractString)
    #@printf "calcRel between %s and %s \n" id1 id2
    if id1=="0" || id2=="0"           # zero
        return 0.0
    end
    old,yng = ped.idMap[id1].seqID < ped.idMap[id2].seqID ? (id1,id2) : (id2,id1)
    oldID = ped.idMap[old].seqID
    yngID = ped.idMap[yng].seqID

    n = yngID - 1
    aijKey = n*(n+1)/2 + oldID
    if haskey(ped.aij,aijKey)
        return ped.aij[aijKey]
    end

    sireOfYng = ped.idMap[yng].sire
    damOfYng  = ped.idMap[yng].dam

    if old==yng                       # aii
        #aii = 1.0 + calcInbreeding!(ped,old)
        aii = 1.0 + 0.5*calcAddRel!(ped,sireOfYng,damOfYng)
        ped.aij[aijKey] = aii
        return (aii)
    end

    aOldDamYoung  = (old=="0" || damOfYng =="0") ? 0.0 : calcAddRel!(ped,old,damOfYng)
    aOldSireYoung = (old=="0" || sireOfYng=="0") ? 0.0 : calcAddRel!(ped,old,sireOfYng)
    aijVal = 0.5*(aOldSireYoung + aOldDamYoung)
    ped.aij[aijKey] = aijVal

    #aij = 0.5*(calcAddRel!(ped,old,sireOfYng) + calcAddRel!(ped,old,damOfYng))
    #ped.aij[yngID,oldID] = aij
    #ped.aij[oldID,yngID] = 1.0
    return aijVal
end

function calcInbreeding!(ped::Pedigree,id::AbstractString)
    #@printf "calcInbreeding for: %s \n" id
    if ped.idMap[id].f > -1.0
        return ped.idMap[id].f
    end
    sireID = ped.idMap[id].sire
    damID  = ped.idMap[id].dam
    if (sireID=="0" || damID=="0" )
        ped.idMap[id].f = 0.0
    else
        ped.idMap[id].f = 0.5*calcAddRel!(ped,sireID,damID)
    end
end

function AInverse(ped::Pedigree)
    ii,jj,vv = HAi(ped)
    hAi      = sparse(ii,jj,vv)
    Ai       = hAi'hAi
    return Ai
end

function HAi(ped::Pedigree)
    ii = Int64[]
    jj = Int64[]
    vv = Float64[]
    for ind in keys(ped.idMap)
        sire = ped.idMap[ind].sire
        dam  = ped.idMap[ind].dam
        sirePos = sire=="0" ? 0 : ped.idMap[sire].seqID
        damPos  = dam =="0" ? 0 : ped.idMap[dam ].seqID
        myPos   = ped.idMap[ind].seqID
        if sirePos>0 && damPos>0
            d = sqrt(4.0/(2 - ped.idMap[sire].f - ped.idMap[dam].f))
            push!(ii,myPos)
            push!(jj,sirePos)
            push!(vv,-0.5*d)
            push!(ii,myPos)
            push!(jj,damPos)
            push!(vv,-0.5*d)
            push!(ii,myPos)
            push!(jj,myPos)
            push!(vv,d)
         elseif sirePos>0
            d = sqrt(4.0/(3 - ped.idMap[sire].f))
            push!(ii,myPos)
            push!(jj,sirePos)
            push!(vv,-0.5*d)
            push!(ii,myPos)
            push!(jj,myPos)
            push!(vv,d)
          elseif damPos>0
            d = sqrt(4.0/(3 - ped.idMap[dam].f))
            push!(ii,myPos)
            push!(jj,damPos)
            push!(vv,-0.5*d)
            push!(ii,myPos)
            push!(jj,myPos)
            push!(vv,d)
        else
            d = 1.0
            push!(ii,myPos)
            push!(jj,myPos)
            push!(vv,d)
        end
    end
    return (ii,jj,vv)
end

function AInverseSlow(ped::Pedigree)
    n = ped.currentID - 1
    Ai = spzeros(n,n)
    pos  = Int64[0,0,0]
    q    = [0.5,0.5,1.0]
    for ind in keys(ped.idMap)
        sire = ped.idMap[ind].sire
        dam  = ped.idMap[ind].dam
        pos[1] = sire=="0" ? 0 : ped.idMap[sire].seqID
        pos[2] = dam =="0" ? 0 : ped.idMap[dam ].seqID
        pos[3] = ped.idMap[ind].seqID
        if pos[1]>0 && pos[2]>0
            q[1] = -0.5
            q[2] = -0.5
            d = 4.0/(2 - ped.idMap[sire].f - ped.idMap[dam].f)
        elseif pos[1]>0
            q[1] = -0.5
            q[2] = 0.0
            d = 4.0/(3 - ped.idMap[sire].f)
        elseif pos[2]>0
            q[1] = 0.0
            q[2] = -0.5
            d = 4.0/(3 - ped.idMap[dam].f)
        else
            q[1] = 0.0
            q[2] = 0.0
            d = 1.0
        end
        for i=1:3
            ii = pos[i]
            if ii>0
                for j=1:3
                    jj = pos[j]
                    if jj>0
                        Ai[ii,jj] += q[i]*q[j]*d
                    end
                end
            end
        end
    end
    return (Ai)
end

function  mkPed(pedFile::AbstractString;header=false,separator=',')
    df  = CSV.read(pedFile,types=[String,String,String],
                    delim=separator,header=header)
    ped = Pedigree(1,Dict{AbstractString,PedNode}(),
                     Dict{Int64, Float64}(),
                     Set(),Set(),Set(),Set(),Array{String,1}())
    fillMap!(ped,df)
    @showprogress "coding pedigree... " for id in keys(ped.idMap)
     code!(ped,id)
    end
    @showprogress "calculating inbreeding... " for id in keys(ped.idMap)
      calcInbreeding!(ped,id)
    end

    ped.IDs=getIDs(ped)

    println("Finished!")
    return ped
end

function getIDs(ped::Pedigree)
    n = length(ped.idMap)
    ids = Array{String}(undef,n)
    for i in ped.idMap
      ids[i[2].seqID] = i[1]
    end
    return ids
end

function getInbreeding(ped::Pedigree)
    n = length(ped.idMap)
    inbreeding = Array{AbstractFloat}(undef,n)
    for i in ped.idMap
      inbreeding[i[2].seqID] = i[2].f
    end
    return inbreeding
end


include("forSSBR.jl")

end # of PedModule
