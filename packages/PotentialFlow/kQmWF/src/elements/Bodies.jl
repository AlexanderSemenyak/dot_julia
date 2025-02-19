module Bodies

using DocStringExtensions


using ..Points
using ..Blobs
using ..Sheets

using ..Freestreams
using ..Doublets

using ..Elements
using ..RigidBodyMotions

import ..Elements: position, impulse, circulation
import ..Motions: induce_velocity, induce_velocity!, mutually_induce_velocity!, self_induce_velocity,
                  self_induce_velocity!, allocate_velocity, advect!, advect, streamfunction, complexpotential
import SchwarzChristoffel: Polygon, ExteriorMap, ConformalMap, PowerMap, addedmass,
                            InverseMap, DerivativeMap, coefficients

import ..Utils:@get, MappedVector

export ConformalBody,Polygon,enforce_no_flow_through!,normal,tangent,
          transform_velocity!,transform_velocity,unit_impulse,addedmass


mutable struct ConformalBody <: Element
    # This mostly serves as a wrapper for the map. The map m contains most
    # geometric data for the body already
    "conformal map that defines the body shape"
    m::ConformalMap
    "inverse of the conformal map"
    minv::InverseMap
    "Jacobian of the conformal map"
    dm::DerivativeMap
    "centroid"
    c::ComplexF64
    "orientation angle (in radians)"
    α::Float64
    "control points on unit circle"
    zetas::Vector{ComplexF64}
    "control points in inertial coordinates in physical plane"
    zs::Vector{ComplexF64}
    "translational velocity"
    ċ::ComplexF64
    "angular velocity"
    α̇::Float64
    "image singularities"
    img::Vector{Element}
end
@kind ConformalBody Singleton

ConformalBody(m::PowerMap,c,α) =
        ConformalBody(m,InverseMap(m),DerivativeMap(m),
        ComplexF64(c),α,ComplexF64[],rigid_transform(m.z,ComplexF64(c),α),ComplexF64(0),0.0,
        Points.Point{Float64}[])

ConformalBody(m::ExteriorMap,c,α) =
        ConformalBody(m,InverseMap(m),DerivativeMap(m),
        ComplexF64(c),α,(1+1e-15)*m.preprev,rigid_transform(m.z,ComplexF64(c),α),ComplexF64(0),0.0,
        Points.Point{Float64}[])

ConformalBody(m::ConformalMap) = ConformalBody(m,ComplexF64(0),0.0)

"""
    ConformalBody <: Elements.Element

Generates a body from a conformal map. This might be a Schwarz-Christoffel map,
in which case the constructor is supplied a polygon, or it might be a power-
series map, in which case the constructor is given a set of complex coefficients.

# Example

```jldoctest
julia> p = Bodies.Polygon([-1.0,0.2,1.0,-1.0],[-1.0,-1.0,0.5,1.0])
Polygon with 4 vertices at
             (-1.0,-1.0) (0.2,-1.0) (1.0,0.5) (-1.0,1.0)
             interior angles/π = [0.5, 0.656, 0.422, 0.422]

julia> Bodies.ConformalBody(p)
Body generated by: Schwarz-Christoffel map of unit circle to exterior of polygon with 4 vertices

  centroid at 0.0 + 0.0im
  angle 0.0

julia> a1 = 1; b1 = 0.1; ccoeff = ComplexF64[0.5(a1+b1),0,0.5(a1-b1)];

julia> Bodies.ConformalBody(ccoeff,ComplexF64(1.0),π/4)
Body generated by: Power series map

  centroid at 1.0 + 0.0im
  angle 0.7854
```
"""
function ConformalBody(p::Polygon,x...)
  m = ExteriorMap(p)
  ConformalBody(m,x...)
end

function ConformalBody(ccoeff::Vector{ComplexF64},x...)
  m = PowerMap(ccoeff)
  ConformalBody(m,x...)
end

ConformalBody() = ConformalBody(PowerMap(ComplexF64(1)))

function Base.show(io::IO, b::ConformalBody)
    println(io, "Body generated by: $(b.m)")
    println(io, "  centroid at $(round(b.c, digits=4))")
    println(io, "  angle $(round(b.α, digits=4))")
end


rigid_transform(z̃::Union{ComplexF64,Vector{ComplexF64}},
                c::ComplexF64,α::Float64) = c .+ z̃*exp(im*α)


Base.length(b::ConformalBody) = b.m.N

"""
    normal(ζ,v,b::ConformalBody)

Returns the normal component of the complex vector(s) `v` in the physical plane
at a point(s) on the surface of body `b`. Each surface point
is specified by its pre-image `ζ` on the unit circle. `v` and `ζ` can be arrays
of points.

# Example

```jldoctest
julia> p = Bodies.Polygon([-1.0,1.0,1.0,-1.0],[-1.0,-1.0,1.0,1.0]);

julia> b = Bodies.ConformalBody(p);

julia> Bodies.normal(exp(im*0),exp(im*π/4),b)
0.7071067811865472
```
"""
function normal(ζ::ComplexF64,v::ComplexF64,b::ConformalBody)
  dz̃, ddz̃ = b.dm(ζ)
  real(v*conj(ζ*dz̃*exp(im*b.α))/abs(dz̃))
end

normal(ζ::Vector{ComplexF64},v::Vector{ComplexF64},b::ConformalBody) =
        map((x,y) -> normal(x,y,b),ζ,v)

"""
    tangent(ζ,v,b::ConformalBody)

Returns the (counter-clockwise) tangent component of the complex vector(s) `v`
in the physical plane at a point(s) on the surface of body `b`. Each surface point
is specified by its pre-image `ζ` on the unit circle. `v` and `ζ` can be arrays
of points.

# Example

```jldoctest
julia> p = Bodies.Polygon([-1.0,1.0,1.0,-1.0],[-1.0,-1.0,1.0,1.0]);

julia> b = Bodies.ConformalBody(p);

julia> Bodies.tangent(exp(im*0),exp(im*π/4),b)
0.7071067811865478
```
"""
function tangent(ζ::ComplexF64,v::ComplexF64,b::ConformalBody)
  dz̃, ddz̃ = b.dm(ζ)
  imag(v*conj(ζ*dz̃*exp(im*b.α))/abs(dz̃))
end

tangent(ζ::Vector{ComplexF64},v::Vector{ComplexF64},b::ConformalBody) =
        map((x,y) -> tangent(x,y,b),ζ,v)

addedmass(b::ConformalBody) = addedmass(b.m)

####

function allocate_conftransform(::ConformalBody)
    nothing
end

Elements.conftransform(ζ::ComplexF64,b::ConformalBody) = b.c + b.m(ζ)*exp(im*b.α)

Elements.conftransform(s::Point{T},b::ConformalBody) where T =
                Point{T}(Elements.conftransform(s.z,b),s.S)

Elements.conftransform(s::Blob{T},b::ConformalBody) where T =
                Blob{T}(Elements.conftransform(s.z,b),s.S,s.δ)

Elements.conftransform(f::Freestream,b::ConformalBody) =
      Freestream(f.U/conj(b.m.ps.ccoeff[1])*exp(im*b.α))


function allocate_inv_conftransform(::ConformalBody)
    nothing
end

Elements.inverse_conftransform(z::ComplexF64,b::ConformalBody) = b.minv((z-b.c)*exp(-im*b.α))

Elements.inverse_conftransform(s::Point{T},b::ConformalBody) where T=
                Point{T}(Elements.inverse_conftransform(s.z,b),s.S)

Elements.inverse_conftransform(s::Blob{T},b::ConformalBody) where T =
                Blob{T}(Elements.inverse_conftransform(s.z,b),s.S,s.δ)

Elements.inverse_conftransform(f::Freestream,b::ConformalBody) =
        Freestream(f.U*conj(b.m.ps.ccoeff[1])*exp(-im*b.α))


function allocate_jacobian(::ConformalBody)
    nothing
end

function Elements.jacobian(ζ::ComplexF64,b::ConformalBody)
  dz, ddz = b.dm(ζ)
  return dz
end

Elements.jacobian(s::T,b::ConformalBody) where T <: Union{Blob,Point} =
                Elements.jacobian(s.z,b)

function allocate_velocity(::ConformalBody)
    @warn("Body kinematics should be initialized manually.  This simply returns a stationary motion")
    RigidBodyMotion(0.0, 0.0)
end

function self_induce_velocity!(motion, ::ConformalBody, t)
    motion.ċ, motion.c̈, motion.α̇ = motion.kin(t)
    motion
end

function induce_velocity(ζ::ComplexF64, b::ConformalBody, t)
  # Also, this is the velocity in the circle plane, not physical plane
    @get b (m, minv, dm, c, α, ċ, α̇, img)
    @get m (ps,)
    @get ps (ccoeff,dcoeff)

    #ζ = minv(z)

    dz̃, ddz̃ = dm(ζ)

    c̃̇ = ċ*exp(-im*α)

    ζ⁻ˡ = 1/ζ^2
    w̃ = c̃̇*conj(ccoeff[1])*ζ⁻ˡ + conj(c̃̇)*(dz̃-ccoeff[1])
    for l = 2:length(dcoeff)
        w̃ += im*(l-1)*α̇*dcoeff[l]*ζ⁻ˡ
        ζ⁻ˡ /= ζ
    end
    # need to return the velocity u+iv, not the usual conjugate velocity
    w̃ = conj(w̃)

    # add the influence of images
    w̃ += induce_velocity(ζ,img,t)

    return w̃

end

induce_velocity(target::T,b::ConformalBody, t) where
            T <: Union{Blob,Point} = induce_velocity(target.z,b,t)

induce_velocity(f::Freestream,b::ConformalBody, t) = -im*b.α̇*f.U

"""
    transform_velocity!(wout, win, targets, body::ConformalBody)

Transforms the velocity `win` in the circle plane of a conformal mapping
to a velocity `wout` that can actually be used to transport the pre-images
of elements in `targets` in this circle plane. This transformation applies the Routh
correction and subtracts the relative motion of the `body`.

# Example

```jldoctest
julia> a1 = 1; b1 = 0.1; ccoeff = ComplexF64[0.5(a1+b1),0,0.5(a1-b1)];

julia> body = Bodies.ConformalBody(ccoeff);

julia> motion = RigidBodyMotion(0,0);

julia> points = Vortex.Point.([-2, 2], 1.0);

julia> Bodies.enforce_no_flow_through!(body, motion, points, 0);

julia> sys = (body,points);

julia> ẋ = (motion, allocate_velocity(points));

julia> self_induce_velocity!(ẋ, sys, 0)
(Rigid Body Motion:
  ċ = 0.0 + 0.0im
  c̈ = 0.0 + 0.0im
  α̇ = 0.0
  α̈ = 0.0
  Constant (ċ = 0 + 0im, α̇ = 0), Complex{Float64}[0.0+0.129977im, 0.0-0.129977im])

julia> Bodies.transform_velocity!(ẋ, ẋ, sys, body)
(Rigid Body Motion:
  ċ = 0.0 + 0.0im
  c̈ = 0.0 + 0.0im
  α̇ = 0.0
  α̈ = 0.0
  Constant (ċ = 0 + 0im, α̇ = 0), Complex{Float64}[0.0+0.785969im, 0.0-0.785969im])
```

    transform_velocity(win, target::ComplexF64, body::ConformalBody)

Returns the velocity in the physical plane from the velocity `win` in the circle plane.

```jldoctest
julia> a1 = 1; b1 = 0.1; ccoeff = ComplexF64[0.5(a1+b1),0,0.5(a1-b1)];

julia> body = Bodies.ConformalBody(ccoeff,0.0+0.0im,π/4);

julia> motion = RigidBodyMotion(1,0);

julia> points = Vortex.Point.([-2, 2], 1.0);

julia> Bodies.enforce_no_flow_through!(body, motion, points, 0);

julia> sys = (body,points);

julia> ζ = exp(-im*π/4);

julia> w̃ = induce_velocity(ζ,sys,0);

julia> w = Bodies.transform_velocity(w̃,ζ,body)
0.7497272298496697 - 0.3058889412948484im
```
"""
function transform_velocity!(wout,win,targets::T,b::ConformalBody) where T <: Union{Tuple,AbstractArray}
  for (i,target) in enumerate(targets)
    wout[i] = transform_velocity(win[i],target,b)
  end
  wout
end

function transform_velocity!(wout,win,targets::T,b::ConformalBody) where T <: Tuple
  for (i,target) in enumerate(targets)
    transform_velocity!(wout[i],win[i],target,b)
  end
  wout
end

function transform_velocity(win,targ::T,b::ConformalBody) where T <: Union{Blob,Point}
  wout = win
  z̃ = b.m(targ.z)
  dz̃, ddz̃ = b.dm(targ.z)
  wout += targ.S*conj(ddz̃)/(4π*im*conj(dz̃))
  wout /= conj(dz̃)
  wout -= b.ċ*exp(-im*b.α) + im*b.α̇*z̃
  wout /= dz̃
  wout
end


function transform_velocity(win,ζ::ComplexF64,b::ConformalBody)
  wout = win
  z̃ = b.m(ζ)
  dz̃, ddz̃ = b.dm(ζ)
  wout /= conj(dz̃*exp(im*b.α))
end

transform_velocity(win,ζ::Vector{ComplexF64},b::ConformalBody) =
      map((x,y) -> transform_velocity(x,y,b),win,ζ)

function transform_velocity!(wout,win,targ::ConformalBody,b::ConformalBody)
    wout = win
end

function transform_velocity!(wout,win,targ::Freestream,b::ConformalBody)
    wout = win
end

transform_velocity!(wout,win,sheet::Sheet,b) = transform_velocity!(wout,win,sheet.blobs,b)

include("bodies/boundary_conditions.jl")

function Elements.complexpotential(ζ::ComplexF64, b::ConformalBody)
  @get b (m, minv, c, α, ċ, α̇, img)
  @get m (ps,)
  @get ps (ccoeff,dcoeff)

  #ζ = minv(z)
  z̃ = m(ζ)

  c̃̇ = ċ*exp(-im*α)

  ζ⁻ˡ = 1/ζ
  F = -c̃̇*conj(ccoeff[1])*ζ⁻ˡ + conj(c̃̇)*(z̃-ccoeff[1]*ζ-ccoeff[2]) - im*α̇*dcoeff[1]
  for l = 2:length(dcoeff)
      F -= im*α̇*dcoeff[l]*ζ⁻ˡ
      ζ⁻ˡ /= ζ
  end

  return F + complexpotential(ζ,img)

end

function Elements.streamfunction(ζ::ComplexF64, b::ConformalBody)
  @get b (m, minv, c, α, ċ, α̇, img)
  @get m (ps,)
  @get ps (ccoeff,dcoeff)

  #ζ = minv(z)
  z̃ = m(ζ)

  c̃̇ = ċ*exp(-im*α)

  ζ⁻ˡ = 1/ζ
  F = -c̃̇*conj(ccoeff[1])*ζ⁻ˡ + conj(c̃̇)*(z̃-ccoeff[1]*ζ-ccoeff[2]) - im*α̇*dcoeff[1]
  for l = 2:length(dcoeff)
      F -= im*α̇*dcoeff[l]*ζ⁻ˡ
      ζ⁻ˡ /= ζ
  end

  return imag(F) + streamfunction(ζ,img)

end

###

function induce_velocity!(ws::Vector, b::ConformalBody, sources::T, t) where T <: Union{Tuple, AbstractArray}
    for source in sources
        induce_velocity!(ws, b, source, t)
    end
    ws
end
function induce_velocity(b::ConformalBody, src, t)
    out = allocate_velocity(b.zs)
    induce_velocity!(out, b, src, t)
end

function induce_velocity!(ws::Vector, b::ConformalBody, src, t)
    _singular_velocity!(ws, b, Elements.unwrap(src), t,
                        kind(Elements.unwrap_src(src)))
end

# Note that we are assuming here that the blobs/points are in the circle plane
function _singular_velocity!(ws, b, src::Blob{T}, t, ::Type{Singleton}) where T
    induce_velocity!(ws, b.zetas, Point{T}(src.z, src.S), t)
end

function _singular_velocity!(ws, b, src, t, ::Type{Singleton})
    induce_velocity!(ws, b.zetas, src, t)
end

function _singular_velocity!(ws, b, src, t, ::Type{Group})
    for i in eachindex(src)
        induce_velocity!(ws, b, src[i], t)
    end
    ws
end

induce_velocity!(m::RigidBodyMotion, target::ConformalBody, source, t) = m

function advect!(body₊::ConformalBody, body₋::ConformalBody, ṗ::RigidBodyMotion, Δt)
    if body₊ != body₋
        body₊.m    = body₋.m
        body₊.minv    = body₋.minv
        body₊.dm   = body₋.dm
        if length(body₊.zs) != length(body₋.zs)
            resize!(body₊.zs, length(body₋.zs))
        end
        body₊.zs   .= body₋.zs
    end
    body₊.c = body₋.c + ṗ.ċ*Δt
    body₊.α = body₋.α + ṗ.α̇*Δt

    @get body₊ (m, c, α)

    @. body₊.zs = rigid_transform(m.z,ComplexF64(c),α)

    return body₊
end

function advect!(f₊::Freestream,f₋::Freestream,w::ComplexF64, Δt)
  f₊ = advect(f₋::Freestream, w, Δt)
  return f₊
end

advect(f₋::Freestream, w::ComplexF64, Δt) = Freestream(f₋.U+w*Δt)

function Elements.impulse(body::ConformalBody)

  @get body (m,α,c,ċ,α̇,img)
  ċ̃ = ċ*exp(-im*α)
  c̃ = c*exp(-im*α)

  impv = addedmass(body)[2:3,:]*[α̇;real(ċ̃);imag(ċ̃)]

  imp = impv[1]+im*impv[2]
  for v in img
    if typeof(v) <: Points.Point
      ζ = image(v.z,body) # image of the img (outside of circle)
      Γ = -v.S # strength of vortex
      # the last terms cancel the direct contribution from
      # the vortex, which is calculated from vortex
      # position in inertial coordinates
      imp += im*Γ*(m.ps.ccoeff[1]*(v.z-ζ)+(m(ζ)+c̃))
    end
  end

  return imp*exp(im*α)

end

"""
    unit_impulse(src, body::ConformalBody)

Compute the impulse per unit circulation of `src` and its associated bound
vortex sheet on the conformally mapped `body` (its image vortex)
`src` can be either a `ComplexF64` or a subtype of `Vortex.PointSource`.
In both cases, the position associated with `src` is interpreted in the
circle plane of the conformal map.
"""
unit_impulse(ζ::ComplexF64, body::ConformalBody) =
          -im*body.m.ps.ccoeff[1]*(ζ - Elements.image(ζ))

unit_impulse(src, body::ConformalBody) = unit_impulse(Elements.position(src), body)

#= stuff to contemplate adding back in





function streamfunction(ζ::ComplexF64, b::PowerBody, Winf::ComplexF64, t)
  @get b (C, D, α, c)

  W̃inf = Winf*exp(im*α)

  F = W̃inf*C[1]*ζ + conj(W̃inf*C[1])/ζ

  imag(F)

end

=#



#=

function impulse(p::Plate)
    @get p (c, B₀, α, Γ, L, A)
    -im*c*Γ - exp(im*α)*π*(0.5L)^2*im*(A[0] - 0.5A[2] - B₀)
end




normal(z, α) = imag(exp(-im*α)*z)
tangent(z, α) = real(exp(-im*α)*z)







"""
    unit_impulse(src, plate::Plate)

Compute the impulse per unit circulation of `src` and its associated bound vortex sheet on `plate` (its image vortex)
`src` can be either a `ComplexF64` or a subtype of `Vortex.PointSource`.
"""
function unit_impulse(z::ComplexF64, plate::Plate)
    z̃ = 2(z - plate.c)*exp(-im*plate.α)/plate.L
    unit_impulse(z̃)
end
unit_impulse(z̃) = -im*(z̃ + real(√(z̃ - 1)*√(z̃ + 1) - z̃))
unit_impulse(src, plate::Plate) = unit_impulse(Elements.position(src), plate)

include("plates/boundary_conditions.jl")
include("plates/circulation.jl")
include("plates/force.jl")

raw"""
    surface_pressure(plate, motion, te_sys, Γs₋, Δt)

Compute the pressure difference across the plate along Chebyshev nodes.

!!! note
    The pressure difference across the bound vortex sheet is given by:
    ```math
        [p]_-^+
      = -\rho \left[ \frac{1}{2}(\boldsymbol{v}^+ + \boldsymbol{v}^-)
                   - \boldsymbol{v}_b
             \right]
             \cdot ( \boldsymbol{\gamma} \times \boldsymbol{\hat{n}})
        +\rho \frac{\mathrm{d}\Gamma}{\mathrm{d}t}
    ```
    where ``\rho`` is the fluid density, ``\boldsymbol{v}^\pm`` is the
    velocity on either side of the plate, ``\boldsymbol{v}_b`` is the local
    velocity of the plate, ``\boldsymbol{\gamma}`` is the bound vortex
    sheet strength, and ``\Gamma`` is the integrated circulation.
    We will compute ``\frac{\mathrm{d}\Gamma}{\mathrm{d}t}`` using finite
    differences.  So we will need the circulation along the plate from a
    previous time-step in order to compute the current pressure
    distribution.  We assume that value of circulation at the trailing
    edge of the plate is equal the the net circulation of all the vorticity
    that has been shed from the trailing edge.

# Arguments

- `plate`: we assume that the `Plate` structure that is passed in
  already enforces the no-flow-through condition
- `motion`: the motion of the plate used to compute ``\boldsymbol{v}_b``
- `te_sys`: the system of vortex elements representing the vorticity
  shed from the trailing edge of the plate
- `Γs₋`: the circulation along the plate's Chebyshev nodes, this
  should be equivalent to calling
  `Vortex.circulation(te_sys) .+ Vortex.bound_circulation(plate)`
  from a previous time-step.
- `Δt`: time-step used to compute ``\frac{\mathrm{d}\Gamma}{\mathrm{d}t}``
  using finite differences

# Returns

- `Δp`: the pressure difference across the plate along Chebyshev nodes
- `Γs₊`: the circulation along the plate at the current time-step
  (this value is used in computing the current `Δp` and can be used as
  the `Γs₋` for computing pressure differences at the **next** time-step)
"""
function surface_pressure(plate, motion, ambient_sys, Γs₋, Δt)
    @get plate (C, ss, α)

    Δp = strength(plate) .* (Chebyshev.firstkind(real.(C), ss) .- tangent(motion.ċ, α))

    Γs₊ = circulation(ambient_sys) .+ bound_circulation(plate)
    Δp .+= (Γs₊ .- Γs₋)./Δt

    Δp, Γs₊
end

"""
    edges(plate)

Return the coordinates of the leading and trailing edges

# Example

```jldoctest
julia> p = Plate(128, 1.0, 0, π/4)
Plate: N = 128, L = 1.0, c = 0.0 + 0.0im, α = 45.0ᵒ
       LESP = 0.0, TESP = 0.0

julia> Plates.edges(p)
(0.3535533905932738 + 0.35355339059327373im, -0.3535533905932738 - 0.35355339059327373im)
```
"""
edges(plate) = plate.zs[end], plate.zs[1]

include("plates/pressure.jl")
=#




end
