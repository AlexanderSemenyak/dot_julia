# This file was generated by the Julia Swagger Code Generator
# Do not modify this file directly. Modify the swagger specification instead.



mutable struct IoK8sApiExtensionsV1beta1Scale <: SwaggerModel
    apiVersion::Any # spec type: Union{ Nothing, String } # spec name: apiVersion
    kind::Any # spec type: Union{ Nothing, String } # spec name: kind
    metadata::Any # spec type: Union{ Nothing, IoK8sApimachineryPkgApisMetaV1ObjectMeta } # spec name: metadata
    spec::Any # spec type: Union{ Nothing, IoK8sApiExtensionsV1beta1ScaleSpec } # spec name: spec
    status::Any # spec type: Union{ Nothing, IoK8sApiExtensionsV1beta1ScaleStatus } # spec name: status

    function IoK8sApiExtensionsV1beta1Scale(;apiVersion=nothing, kind=nothing, metadata=nothing, spec=nothing, status=nothing)
        o = new()
        validate_property(IoK8sApiExtensionsV1beta1Scale, Symbol("apiVersion"), apiVersion)
        setfield!(o, Symbol("apiVersion"), apiVersion)
        validate_property(IoK8sApiExtensionsV1beta1Scale, Symbol("kind"), kind)
        setfield!(o, Symbol("kind"), kind)
        validate_property(IoK8sApiExtensionsV1beta1Scale, Symbol("metadata"), metadata)
        setfield!(o, Symbol("metadata"), metadata)
        validate_property(IoK8sApiExtensionsV1beta1Scale, Symbol("spec"), spec)
        setfield!(o, Symbol("spec"), spec)
        validate_property(IoK8sApiExtensionsV1beta1Scale, Symbol("status"), status)
        setfield!(o, Symbol("status"), status)
        o
    end
end # type IoK8sApiExtensionsV1beta1Scale

const _property_map_IoK8sApiExtensionsV1beta1Scale = Dict{Symbol,Symbol}(Symbol("apiVersion")=>Symbol("apiVersion"), Symbol("kind")=>Symbol("kind"), Symbol("metadata")=>Symbol("metadata"), Symbol("spec")=>Symbol("spec"), Symbol("status")=>Symbol("status"))
const _property_types_IoK8sApiExtensionsV1beta1Scale = Dict{Symbol,String}(Symbol("apiVersion")=>"String", Symbol("kind")=>"String", Symbol("metadata")=>"IoK8sApimachineryPkgApisMetaV1ObjectMeta", Symbol("spec")=>"IoK8sApiExtensionsV1beta1ScaleSpec", Symbol("status")=>"IoK8sApiExtensionsV1beta1ScaleStatus")
Base.propertynames(::Type{ IoK8sApiExtensionsV1beta1Scale }) = collect(keys(_property_map_IoK8sApiExtensionsV1beta1Scale))
Swagger.property_type(::Type{ IoK8sApiExtensionsV1beta1Scale }, name::Symbol) = Union{Nothing,eval(Meta.parse(_property_types_IoK8sApiExtensionsV1beta1Scale[name]))}
Swagger.field_name(::Type{ IoK8sApiExtensionsV1beta1Scale }, property_name::Symbol) =  _property_map_IoK8sApiExtensionsV1beta1Scale[property_name]

function check_required(o::IoK8sApiExtensionsV1beta1Scale)
    true
end

function validate_property(::Type{ IoK8sApiExtensionsV1beta1Scale }, name::Symbol, val)
end
