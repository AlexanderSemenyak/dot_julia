# This file was generated by the Julia Swagger Code Generator
# Do not modify this file directly. Modify the swagger specification instead.



mutable struct IoK8sApiAppsV1beta2RollingUpdateDaemonSet <: SwaggerModel
    maxUnavailable::Any # spec type: Union{ Nothing, IoK8sApimachineryPkgUtilIntstrIntOrString } # spec name: maxUnavailable

    function IoK8sApiAppsV1beta2RollingUpdateDaemonSet(;maxUnavailable=nothing)
        o = new()
        validate_property(IoK8sApiAppsV1beta2RollingUpdateDaemonSet, Symbol("maxUnavailable"), maxUnavailable)
        setfield!(o, Symbol("maxUnavailable"), maxUnavailable)
        o
    end
end # type IoK8sApiAppsV1beta2RollingUpdateDaemonSet

const _property_map_IoK8sApiAppsV1beta2RollingUpdateDaemonSet = Dict{Symbol,Symbol}(Symbol("maxUnavailable")=>Symbol("maxUnavailable"))
const _property_types_IoK8sApiAppsV1beta2RollingUpdateDaemonSet = Dict{Symbol,String}(Symbol("maxUnavailable")=>"IoK8sApimachineryPkgUtilIntstrIntOrString")
Base.propertynames(::Type{ IoK8sApiAppsV1beta2RollingUpdateDaemonSet }) = collect(keys(_property_map_IoK8sApiAppsV1beta2RollingUpdateDaemonSet))
Swagger.property_type(::Type{ IoK8sApiAppsV1beta2RollingUpdateDaemonSet }, name::Symbol) = Union{Nothing,eval(Meta.parse(_property_types_IoK8sApiAppsV1beta2RollingUpdateDaemonSet[name]))}
Swagger.field_name(::Type{ IoK8sApiAppsV1beta2RollingUpdateDaemonSet }, property_name::Symbol) =  _property_map_IoK8sApiAppsV1beta2RollingUpdateDaemonSet[property_name]

function check_required(o::IoK8sApiAppsV1beta2RollingUpdateDaemonSet)
    true
end

function validate_property(::Type{ IoK8sApiAppsV1beta2RollingUpdateDaemonSet }, name::Symbol, val)
end
