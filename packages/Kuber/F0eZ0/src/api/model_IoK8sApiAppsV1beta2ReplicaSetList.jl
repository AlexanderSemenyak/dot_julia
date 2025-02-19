# This file was generated by the Julia Swagger Code Generator
# Do not modify this file directly. Modify the swagger specification instead.



mutable struct IoK8sApiAppsV1beta2ReplicaSetList <: SwaggerModel
    apiVersion::Any # spec type: Union{ Nothing, String } # spec name: apiVersion
    items::Any # spec type: Union{ Nothing, Vector{IoK8sApiAppsV1beta2ReplicaSet} } # spec name: items
    kind::Any # spec type: Union{ Nothing, String } # spec name: kind
    metadata::Any # spec type: Union{ Nothing, IoK8sApimachineryPkgApisMetaV1ListMeta } # spec name: metadata

    function IoK8sApiAppsV1beta2ReplicaSetList(;apiVersion=nothing, items=nothing, kind=nothing, metadata=nothing)
        o = new()
        validate_property(IoK8sApiAppsV1beta2ReplicaSetList, Symbol("apiVersion"), apiVersion)
        setfield!(o, Symbol("apiVersion"), apiVersion)
        validate_property(IoK8sApiAppsV1beta2ReplicaSetList, Symbol("items"), items)
        setfield!(o, Symbol("items"), items)
        validate_property(IoK8sApiAppsV1beta2ReplicaSetList, Symbol("kind"), kind)
        setfield!(o, Symbol("kind"), kind)
        validate_property(IoK8sApiAppsV1beta2ReplicaSetList, Symbol("metadata"), metadata)
        setfield!(o, Symbol("metadata"), metadata)
        o
    end
end # type IoK8sApiAppsV1beta2ReplicaSetList

const _property_map_IoK8sApiAppsV1beta2ReplicaSetList = Dict{Symbol,Symbol}(Symbol("apiVersion")=>Symbol("apiVersion"), Symbol("items")=>Symbol("items"), Symbol("kind")=>Symbol("kind"), Symbol("metadata")=>Symbol("metadata"))
const _property_types_IoK8sApiAppsV1beta2ReplicaSetList = Dict{Symbol,String}(Symbol("apiVersion")=>"String", Symbol("items")=>"Vector{IoK8sApiAppsV1beta2ReplicaSet}", Symbol("kind")=>"String", Symbol("metadata")=>"IoK8sApimachineryPkgApisMetaV1ListMeta")
Base.propertynames(::Type{ IoK8sApiAppsV1beta2ReplicaSetList }) = collect(keys(_property_map_IoK8sApiAppsV1beta2ReplicaSetList))
Swagger.property_type(::Type{ IoK8sApiAppsV1beta2ReplicaSetList }, name::Symbol) = Union{Nothing,eval(Meta.parse(_property_types_IoK8sApiAppsV1beta2ReplicaSetList[name]))}
Swagger.field_name(::Type{ IoK8sApiAppsV1beta2ReplicaSetList }, property_name::Symbol) =  _property_map_IoK8sApiAppsV1beta2ReplicaSetList[property_name]

function check_required(o::IoK8sApiAppsV1beta2ReplicaSetList)
    (getproperty(o, Symbol("items")) === nothing) && (return false)
    true
end

function validate_property(::Type{ IoK8sApiAppsV1beta2ReplicaSetList }, name::Symbol, val)
end
