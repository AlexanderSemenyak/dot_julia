function LightXML_plunge(xtmp::Array{LightXML.XMLElement,1}, str::AbstractString)
  xtmp2 = Array{LightXML.XMLElement,1}()
  for i = 1:length(xtmp)
    append!(xtmp2, get_elements_by_tagname(getindex(xtmp, i), str))
  end
  return xtmp2
end

function LightXML_findall(xtmp::Array{LightXML.XMLElement,1}, str::String)
  S = string.(split(str, "/"))
  for i = 1:length(S)
    xtmp = LightXML_plunge(xtmp, getindex(S, i))
  end
  return xtmp
end
LightXML_findall(xdoc::LightXML.XMLDocument, str::String) = LightXML_findall([LightXML.root(xdoc)], str)
LightXML_findall(xtmp::LightXML.XMLElement, str::String) = LightXML_findall([xtmp], str)
#
function LightXML_str!(v::String, x::LightXML.XMLElement, s::String)
  Q = LightXML_findall(x, s)
  if isempty(Q) == false
    v = content(Q[1])
  end
  return v
end
LightXML_float!(v::Float64, x::LightXML.XMLElement, s::String) = Float64(Meta.parse(LightXML_str!(string(v), x, s)))
LightXML_float32!(v::Float32, x::LightXML.XMLElement, s::String) = Float32(Meta.parse(LightXML_str!(string(v), x, s)))

function FDSN_sta_xml(string_data::String)
    xroot = LightXML.parse_string(string_data)
    N = length(LightXML_findall(xroot, "Network/Station/Channel"))

    ID    = Array{String,1}(undef, N)
    NAME  = Array{String,1}(undef, N)
    FS    = Array{Float64,1}(undef, N)
    LOC   = Array{GeoLoc,1}(undef, N)
    UNITS = Array{String,1}(undef, N)
    GAIN  = Array{Float64,1}(undef, N)
    RESP  = Array{PZResp,1}(undef, N)
    MISC  = Array{Dict{String,Any}}(undef, N)
    for j = 1:N
        MISC[j] = Dict{String,Any}()
    end
    y = 0

    xnet = LightXML_findall(xroot, "Network")
    for net in xnet
        nn = attribute(net, "code")

        xsta = LightXML_findall(net, "Station")
        for sta in xsta
            ss = attribute(sta, "code")
            loc_tmp = GeoLoc()
            loc_tmp.lat = LightXML_float!(0.0, sta, "Latitude")
            loc_tmp.lon = LightXML_float!(0.0, sta, "Longitude")
            loc_tmp.el = LightXML_float!(0.0, sta, "Elevation")
            name = LightXML_str!("0.0", sta, "Site/Name")

            xcha = LightXML_findall(sta, "Channel")
            for cha in xcha
                y += 1
                czs = Array{Complex{Float32},1}(undef, 0)
                cps = Array{Complex{Float32},1}(undef, 0)
                ID[y]               = join([nn, ss, attribute(cha,"locationCode"), attribute(cha,"code")],'.')
                NAME[y]             = identity(name)
                FS[y]               = LightXML_float!(0.0, cha, "SampleRate")
                LOC[y]              = GeoLoc()
                LOC[y].lat          = loc_tmp.lat
                LOC[y].lon          = loc_tmp.lon
                LOC[y].el           = loc_tmp.el
                LOC[y].az           = LightXML_float!(0.0, cha, "Azimuth")
                LOC[y].inc          = LightXML_float!(0.0, cha, "Dip") - 90.0
                GAIN[y]             = 1.0
                MISC[y]["normfreq"] = 1.0
                MISC[y]["ClockDrift"] = LightXML_float!(0.0, cha, "ClockDrift")

                xresp = LightXML_findall(cha, "Response")
                if !isempty(xresp)
                    MISC[y]["normfreq"] = LightXML_float!(0.0, xresp[1], "InstrumentSensitivity/Frequency")
                    GAIN[y]             = LightXML_float!(1.0, xresp[1], "InstrumentSensitivity/Value")
                    UNITS[y]            = replace(LightXML_str!("unknown", xresp[1], "InstrumentSensitivity/InputUnits/Name"), "**" => "")

                    xstages = LightXML_findall(xresp[1], "Stage")
                    for stage in xstages
                        pz = LightXML_findall(stage, "PolesZeros")
                        for j = 1:length(pz)
                            append!(czs, [complex(LightXML_float32!(0.0f0, z, "Real"), LightXML_float32!(0.0f0, z, "Imaginary")) for z in LightXML_findall(pz[j], "Zero")])
                            append!(cps, [complex(LightXML_float32!(0.0f0, p, "Real"), LightXML_float32!(0.0f0, p, "Imaginary")) for p in LightXML_findall(pz[j], "Pole")])
                        end
                    end
                end
                NZ = length(czs)
                NP = length(cps)
                if NZ < NP
                  append!(czs, zeros(Complex{Float32}, NP-NZ))
                end
                RESP[y] = PZResp(1.0f0, cps, czs)
            end
        end
    end
    LightXML.free(xroot)
    return ID, NAME, LOC, FS, GAIN, RESP, UNITS, MISC
end
