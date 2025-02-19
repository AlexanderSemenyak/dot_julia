# This file was generated by the Julia Swagger Code Generator
# Do not modify this file directly. Modify the swagger specification instead.



mutable struct IoK8sApiExtensionsV1beta1RollingUpdateDeployment <: SwaggerModel
    maxSurge::Any # spec type: Union{ Nothing, IoK8sApimachineryPkgUtilIntstrIntOrString } # spec name: maxSurge
    maxUnavailable::Any # spec type: Union{ Nothing, IoK8sApimachineryPkgUtilIntstrIntOrString } # spec name: maxUnavailable

    function IoK8sApiExtensionsV1beta1RollingUpdateDeployment(;maxSurge=nothing, maxUnavailable=nothing)
        o = new()
        validate_property(IoK8sApiExtensionsV1beta1RollingUpdateDeployment, Symbol("maxSurge"), maxSurge)
        setfield!(o, Symbol("maxSurge"), maxSurge)
        validate_property(IoK8sApiExtensionsV1beta1RollingUpdateDeployment, Symbol("maxUnavailable"), maxUnavailable)
        setfield!(o, Symbol("maxUnavailable"), maxUnavailable)
        o
    end
end # type IoK8sApiExtensionsV1beta1RollingUpdateDeployment

const _property_map_IoK8sApiExtensionsV1beta1RollingUpdateDeployment = Dict{Symbol,Symbol}(Symbol("maxSurge")=>Symbol("maxSurge"), Symbol("maxUnavailable")=>Symbol("maxUnavailable"))
const _property_types_IoK8sApiExtensionsV1beta1RollingUpdateDeployment = Dict{Symbol,String}(Symbol("maxSurge")=>"IoK8sApimachineryPkgUtilIntstrIntOrString", Symbol("maxUnavailable")=>"IoK8sApimachineryPkgUtilIntstrIntOrString")
Base.propertynames(::Type{ IoK8sApiExtensionsV1beta1RollingUpdateDeployment }) = collect(keys(_property_map_IoK8sApiExtensionsV1beta1RollingUpdateDeployment))
Swagger.property_type(::Type{ IoK8sApiExtensionsV1beta1RollingUpdateDeployment }, name::Symbol) = Union{Nothing,eval(Meta.parse(_property_types_IoK8sApiExtensionsV1beta1RollingUpdateDeployment[name]))}
Swagger.field_name(::Type{ IoK8sApiExtensionsV1beta1RollingUpdateDeployment }, property_name::Symbol) =  _property_map_IoK8sApiExtensionsV1beta1RollingUpdateDeployment[property_name]

function check_required(o::IoK8sApiExtensionsV1beta1RollingUpdateDeployment)
    true
end

function validate_property(::Type{ IoK8sApiExtensionsV1beta1RollingUpdateDeployment }, name::Symbol, val)
end
