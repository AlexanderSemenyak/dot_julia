using Test
using StaticArrays: SVector
using LinearAlgebra: dot
using QuantumLattices.Essentials.DegreesOfFreedom
using QuantumLattices.Essentials.Spatials: PID,pidtype,rcoord,icoord
using QuantumLattices.Mathematics.AlgebraOverFields: ID
import QuantumLattices.Interfaces: dimension,decompose
import QuantumLattices.Essentials.DegreesOfFreedom: twist

struct DID <: IID nambu::Int end
Base.adjoint(sl::DID)=DID(3-sl.nambu)

struct DIndex{S} <: Index{PID{S},DID}
    scope::S
    site::Int
    nambu::Int
end
Base.fieldnames(::Type{<:DIndex})=(:scope,:site,:nambu)
Base.union(::Type{P},::Type{I}) where {P<:PID,I<:DID}=DIndex{fieldtype(P,:scope)}
function twist(id::OID{<:DIndex},vectors::AbstractVector{<:AbstractVector{Float}},values::AbstractVector{Float})
    phase=  length(vectors)==1 ? exp(2.0im*pi*dot(decompose(id.icoord,vectors[1]),values)) :
            length(vectors)==2 ? exp(2.0im*pi*dot(decompose(id.icoord,vectors[1],vectors[2]),values)) :
            length(vectors)==3 ? exp(2.0im*pi*dot(decompose(id.icoord,vectors[1],vectors[2],vectors[3]),values)) :
            error("twist error: not supported number of input basis vectors.")
    id.index.nambu==1 ? phase : conj(phase)
end

struct DFock <: Internal{DID}
    atom::Int
    nnambu::Int
end
dimension(f::DFock)=f.nnambu
Base.getindex(f::DFock,i::Int)=DID(i)

struct DOperator{N,V<:Number,I<:ID{<:NTuple{N,OID}}} <: Operator{N,V,I}
    value::V
    id::I
    DOperator(value::Number,id::ID{<:NTuple{N,OID}}) where N=new{N,typeof(value),typeof(id)}(value,id)
end

@testset "Index" begin
    index=DIndex(PID('S',4),DID(1))
    @test index|>pidtype==PID{Char}
    @test index|>typeof|>pidtype==PID{Char}
    @test index|>iidtype==DID
    @test index|>typeof|>iidtype==DID
    @test index|>pid==PID('S',4)
    @test index|>iid==DID(1)
    @test index|>adjoint==DIndex('S',4,2)
    @test union(PID,IID)==Index{PID,IID}
    @test union(index|>pidtype,index|>iidtype)==index|>typeof
end

@testset "IndexToTuple" begin
    index=DIndex(PID('S',4),DID(1))
    @test directindextotuple(index)==('S',4,1)
    filteredindextotuple=FilteredAttributes(DIndex)
    @test filteredindextotuple==FilteredAttributes(:scope,:site,:nambu)
    @test filteredindextotuple|>length==3
    @test filteredindextotuple|>typeof|>length==3
    @test filteredindextotuple(index)==('S',4,1)
    @test filter(attr->attr≠:scope,filteredindextotuple)(index)==(4,1)
    @test filter(attr->attr≠:nambu,filteredindextotuple)(index)==('S',4)
    @test filter(attr->attr∉(:site,:nambu),filteredindextotuple)(index)==('S',)
end

@testset "Internal" begin
    it=DFock(1,2)
    @test it|>eltype==DID
    @test it|>typeof|>eltype==DID
    @test it==deepcopy(it)
    @test isequal(it,deepcopy(it))
    @test it|>string=="DFock(atom=1,nnambu=2)"
    @test it|>collect==[DID(1),DID(2)]
end

@testset "IDFConfig" begin
    config=IDFConfig{DFock}(pid->DFock((pid.site-1)%2+1,2),[PID(1,1),PID(1,2)])
    @test convert(Dict,config)==Dict(PID(1,1)=>DFock(1,2),PID(1,2)=>DFock(2,2))
    replace!(config,PID(2,1),PID(2,2))
    @test convert(Dict,config)==Dict(PID(2,1)=>DFock(1,2),PID(2,2)=>DFock(2,2))
end

@testset "Table" begin
    by=filter(attr->attr≠:nambu,FilteredAttributes(DIndex))

    table=Table([DIndex(1,1,1),DIndex(1,1,2)])
    @test table==Dict(DIndex(1,1,1)=>1,DIndex(1,1,2)=>2)
    table=Table([DIndex(1,1,1),DIndex(1,1,2)],by=by)
    @test table==Dict(DIndex(1,1,1)=>1,DIndex(1,1,2)=>1)

    config=IDFConfig{DFock}(pid->DFock((pid.site-1)%2+1,2),[PID(1,1),PID(1,2)])
    inds1=(DIndex(PID(1,1),iid) for iid in DFock(1,2))|>collect
    inds2=(DIndex(PID(1,2),iid) for iid in DFock(2,2))|>collect
    @test Table(config)==Table([inds1;inds2])
    @test Table(config,by=by)==Table([inds1;inds2],by=by)
    @test Table(config)==union(Table(inds1),Table(inds2))
    @test Table(config,by=by)|>reverse==Dict(1=>Set([DIndex(1,1,1),DIndex(1,1,2)]),2=>Set([DIndex(1,2,1),DIndex(1,2,2)]))
end

@testset "OID" begin
    oid=OID(DIndex(1,1,1),rcoord=SVector(0.0,-0.0),icoord=SVector(0.0,0.0),seq=1)
    @test oid'==OID(DIndex(1,1,2),rcoord=SVector(0.0,0.0),icoord=SVector(0.0,0.0),seq=1)
    @test hash(oid,UInt(1))==hash(OID(DIndex(1,1,1),rcoord=SVector(0.0,0.0),icoord=SVector(0.0,0.0),seq=1),UInt(1))
    @test propertynames(ID{<:NTuple{2,OID}},true)==(:contents,:indexes,:rcoords,:icoords)
    @test propertynames(ID{<:NTuple{2,OID}},false)==(:indexes,:rcoords,:icoords)
    @test fieldnames(OID)==(:index,:rcoord,:icoord,:seq)
    @test string(oid)=="OID(DIndex(1,1,1),[0.0,0.0],[0.0,0.0],1)"
    @test ID(oid',oid)'==ID(oid',oid)
    @test isHermitian(ID(oid',oid))==true
    @test isHermitian(ID(oid,oid))==false
end

@testset "Operator" begin
    opt=DOperator(1.0im,(DIndex(1,2,2),DIndex(1,1,1)),rcoords=(SVector(1.0,0.0),SVector(0.0,0.0)),icoords=(SVector(2.0,0.0),SVector(0.0,0.0)),seqs=(2,1))
    @test opt'==DOperator(-1.0im,(DIndex(1,1,2),DIndex(1,2,1)),rcoords=(SVector(0.0,0.0),SVector(1.0,0.0)),icoords=(SVector(0.0,0.0),SVector(2.0,0.0)),seqs=(1,2))
    @test isHermitian(opt)==false
    @test string(opt)=="DOperator(value=1.0im,id=ID(OID(DIndex(1,2,2),[1.0,0.0],[2.0,0.0],2),OID(DIndex(1,1,1),[0.0,0.0],[0.0,0.0],1)))"
    @test twist(opt,[[1.0,0.0],[0.0,1.0]],[0.1,0.0])≈replace(opt,value=1.0im*conj(exp(2im*pi*0.2)))

    opt=DOperator(1.0,(DIndex(1,1,2),DIndex(1,1,1)),rcoords=(SVector(0.5,0.5),SVector(0.5,0.5)),icoords=(SVector(1.0,1.0),SVector(1.0,1.0)),seqs=(1,1))
    @test opt'==opt
    @test isHermitian(opt)==true

    opt=DOperator(1.0,(DIndex(1,1,2),DIndex(1,1,1)),rcoords=(SVector(0.5,0.5),SVector(0.0,0.5)),icoords=(SVector(1.0,1.0),SVector(0.0,1.0)),seqs=(1,1))
    @test rcoord(opt)==SVector(0.5,0.0)
    @test icoord(opt)==SVector(1.0,0.0)

    opt=DOperator(1.0,ID(OID(DIndex(1,1,2),SVector(0.5,0.0),SVector(1.0,0.0),1)))
    @test rcoord(opt)==SVector(0.5,0.0)
    @test icoord(opt)==SVector(1.0,0.0)
end

@testset "Operators" begin
    opt1=DOperator(1.0im,(DIndex(1,2,2),DIndex(1,1,1)),rcoords=(SVector(1.0,0.0),SVector(0.0,0.0)),icoords=(SVector(2.0,0.0),SVector(0.0,0.0)),seqs=(2,1))
    opt2=DOperator(1.0,(DIndex(1,1,2),DIndex(1,1,1)),rcoords=(SVector(0.0,0.0),SVector(0.0,0.0)),icoords=(SVector(0.0,0.0),SVector(0.0,0.0)),seqs=(1,1))
    opts=Operators(opt1,opt2)
    @test opts'==Operators(opt1',opt2')
    @test opts'+opts==Operators(opt1,opt1',opt2*2)
    @test isHermitian(opts)==false
    @test isHermitian(opts'+opts)==true
end
