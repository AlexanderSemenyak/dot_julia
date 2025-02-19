# This file was generated by the Julia Swagger Code Generator
# Do not modify this file directly. Modify the swagger specification instead.



mutable struct IoK8sApiAppsV1beta2DaemonSetSpec <: SwaggerModel
    minReadySeconds::Any # spec type: Union{ Nothing, Int32 } # spec name: minReadySeconds
    revisionHistoryLimit::Any # spec type: Union{ Nothing, Int32 } # spec name: revisionHistoryLimit
    selector::Any # spec type: Union{ Nothing, IoK8sApimachineryPkgApisMetaV1LabelSelector } # spec name: selector
    template::Any # spec type: Union{ Nothing, IoK8sApiCoreV1PodTemplateSpec } # spec name: template
    updateStrategy::Any # spec type: Union{ Nothing, IoK8sApiAppsV1beta2DaemonSetUpdateStrategy } # spec name: updateStrategy

    function IoK8sApiAppsV1beta2DaemonSetSpec(;minReadySeconds=nothing, revisionHistoryLimit=nothing, selector=nothing, template=nothing, updateStrategy=nothing)
        o = new()
        validate_property(IoK8sApiAppsV1beta2DaemonSetSpec, Symbol("minReadySeconds"), minReadySeconds)
        setfield!(o, Symbol("minReadySeconds"), minReadySeconds)
        validate_property(IoK8sApiAppsV1beta2DaemonSetSpec, Symbol("revisionHistoryLimit"), revisionHistoryLimit)
        setfield!(o, Symbol("revisionHistoryLimit"), revisionHistoryLimit)
        validate_property(IoK8sApiAppsV1beta2DaemonSetSpec, Symbol("selector"), selector)
        setfield!(o, Symbol("selector"), selector)
        validate_property(IoK8sApiAppsV1beta2DaemonSetSpec, Symbol("template"), template)
        setfield!(o, Symbol("template"), template)
        validate_property(IoK8sApiAppsV1beta2DaemonSetSpec, Symbol("updateStrategy"), updateStrategy)
        setfield!(o, Symbol("updateStrategy"), updateStrategy)
        o
    end
end # type IoK8sApiAppsV1beta2DaemonSetSpec

const _property_map_IoK8sApiAppsV1beta2DaemonSetSpec = Dict{Symbol,Symbol}(Symbol("minReadySeconds")=>Symbol("minReadySeconds"), Symbol("revisionHistoryLimit")=>Symbol("revisionHistoryLimit"), Symbol("selector")=>Symbol("selector"), Symbol("template")=>Symbol("template"), Symbol("updateStrategy")=>Symbol("updateStrategy"))
const _property_types_IoK8sApiAppsV1beta2DaemonSetSpec = Dict{Symbol,String}(Symbol("minReadySeconds")=>"Int32", Symbol("revisionHistoryLimit")=>"Int32", Symbol("selector")=>"IoK8sApimachineryPkgApisMetaV1LabelSelector", Symbol("template")=>"IoK8sApiCoreV1PodTemplateSpec", Symbol("updateStrategy")=>"IoK8sApiAppsV1beta2DaemonSetUpdateStrategy")
Base.propertynames(::Type{ IoK8sApiAppsV1beta2DaemonSetSpec }) = collect(keys(_property_map_IoK8sApiAppsV1beta2DaemonSetSpec))
Swagger.property_type(::Type{ IoK8sApiAppsV1beta2DaemonSetSpec }, name::Symbol) = Union{Nothing,eval(Meta.parse(_property_types_IoK8sApiAppsV1beta2DaemonSetSpec[name]))}
Swagger.field_name(::Type{ IoK8sApiAppsV1beta2DaemonSetSpec }, property_name::Symbol) =  _property_map_IoK8sApiAppsV1beta2DaemonSetSpec[property_name]

function check_required(o::IoK8sApiAppsV1beta2DaemonSetSpec)
    (getproperty(o, Symbol("selector")) === nothing) && (return false)
    (getproperty(o, Symbol("template")) === nothing) && (return false)
    true
end

function validate_property(::Type{ IoK8sApiAppsV1beta2DaemonSetSpec }, name::Symbol, val)
end
