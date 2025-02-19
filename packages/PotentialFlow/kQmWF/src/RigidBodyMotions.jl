module RigidBodyMotions

export RigidBodyMotion, Kinematics, d_dt

using DocStringExtensions
import ForwardDiff
import Base: +, *, -, >>, <<, show

"""
An abstract type for types that takes in time and returns `(ċ, c̈, α̇)`.
"""
abstract type Kinematics end

"""
An abstract type for real-valued functions of time.
"""
abstract type Profile end

"""
    RigidBodyMotion

A type to store the plate's current kinematics

# Fields

- `ċ`: current centroid velocity
- `c̈`: current centroid acceleration
- `α̇`: current angular velocity
- `α̈`: current angular acceleration
- `kin`: a [`Kinematics`](@ref) structure

The first three fields are meant as a cache of the current kinematics
while the `kin` field can be used to find the plate kinematics at any time.
"""
mutable struct RigidBodyMotion
    ċ::ComplexF64
    c̈::ComplexF64
    α̇::Float64
    α̈::Float64

    kin::Kinematics
end

RigidBodyMotion(ċ, α̇) = RigidBodyMotion(complex(ċ), 0.0im, float(α̇), 0.0, Constant(ċ, α̇))
RigidBodyMotion(kin::Kinematics) = RigidBodyMotion(kin(0)..., kin)
(m::RigidBodyMotion)(t) = m.kin(t)

function show(io::IO, m::RigidBodyMotion)
    println(io, "Rigid Body Motion:")
    println(io, "  ċ = $(round(m.ċ, digits=2))")
    println(io, "  c̈ = $(round(m.c̈, digits=2))")
    println(io, "  α̇ = $(round(m.α̇, digits=2))")
    println(io, "  α̈ = $(round(m.α̈, digits=2))")
    print(io, "  $(m.kin)")
end

#=
Kinematics
=#


struct Constant{C <: Complex, A <: Real} <: Kinematics
    ċ::C
    α̇::A
end
Constant(ċ, α̇) = Constant(complex(ċ), α̇)
(c::Constant{C})(t) where C = c.ċ, zero(C), c.α̇, zero(C)
show(io::IO, c::Constant) = print(io, "Constant (ċ = $(c.ċ), α̇ = $(c.α̇))")

"""
    Pitchup <: Kinematics

Kinematics describing a pitchup motion (horizontal translation with rotation)

# Constructors
# Fields
$(FIELDS)
"""
struct Pitchup <: Kinematics
    "Freestream velocity"
    U₀::Float64
    "Axis of rotation, relative to the plate centroid"
    a::Float64

    "Non-dimensional pitch rate ``K = \\dot{\\alpha}_0\\frac{c}{2U_0}``"
    K::Float64

    "Initial angle of attack"
    α₀::Float64
    "Nominal start of pitch up"
    t₀::Float64

    "Total pitching angle"
    Δα::Float64

    α::Profile
    α̇::Profile
    α̈::Profile
end

function Pitchup(U₀, a, K, α₀, t₀, Δα, ramp)
    Δt = 0.5Δα/K
    p = ConstantProfile(α₀) + 2K*((ramp >> t₀) - (ramp >> (t₀ + Δt)))
    ṗ = d_dt(p)
    p̈ = d_dt(ṗ)
    Pitchup(U₀, a, K, α₀, t₀, Δα, p, ṗ, p̈)
end

function (p::Pitchup)(t)
    α = p.α(t)
    α̇ = p.α̇(t)
    α̈ = p.α̈(t)

    ċ = p.U₀ - p.a*im*α̇*exp(im*α)
    if (t - p.t₀) > p.Δα/p.K
        c̈ = 0.0im
    else
        c̈ = p.a*exp(im*α)*(α̇^2 - im*α̈)
    end

    return ċ, c̈, α̇, α̈
end

"""
    PitchHeave <: Kinematics

Kinematics describing an oscillatory pitching and heaving (i.e. plunging) motion

# Constructors
# Fields
$(FIELDS)
"""
struct PitchHeave <: Kinematics
    "Freestream velocity"
    U₀::Float64

    "Axis of pitch rotation, relative to the plate centroid"
    a::Float64

    "Reduced frequency ``K = \\frac{\\Omega c}{2U_0}``"
    K::Float64

    "Phase lag of pitch to heave (in radians)"
    ϕ::Float64

    "Mean angle of attack"
    α₀::Float64

    "Amplitude of pitching"
    Δα::Float64

    "Amplitude of translational heaving"
    A::Float64

    Y::Profile
    Ẏ::Profile
    Ÿ::Profile

    α::Profile
    α̇::Profile
    α̈::Profile
end

function PitchHeave(U₀, a, K, ϕ, α₀, Δα, A)
    p = A*Sinusoid(2K)
    ṗ = d_dt(p)
    p̈ = d_dt(ṗ)
    Δt = ϕ/(2K)
    α = ConstantProfile(α₀) + Δα*(Sinusoid(2K) >> Δt)
    α̇ = d_dt(α)
    α̈ = d_dt(α̇)
    PitchHeave(U₀, a, K, ϕ, α₀, Δα, A, p, ṗ, p̈, α, α̇, α̈)
end

function (p::PitchHeave)(t)
    α = p.α(t)
    α̇ = p.α̇(t)
    α̈ = p.α̈(t)

    # c will be update in the integration
    ċ = p.U₀ + im*p.Ẏ(t) - p.a*im*α̇*exp(im*α)
    c̈ = im*p.Ÿ(t) + p.a*exp(im*α)*(α̇^2 - im*α̈)

    return ċ, c̈, α̇, α̈
end

#=
Profiles
=#

"""
    ConstantProfile(c::Number)

Create a profile consisting of a constant `c`.

# Example

```jldoctest
julia> p = RigidBodyMotions.ConstantProfile(1.0)
Constant (1.0)
```
"""
struct ConstantProfile <: Profile
    c::Number
end

function show(io::IO, p::ConstantProfile)
    print(io, "Constant ($(p.c))")
end

(p::ConstantProfile)(t) = p.c

struct DerivativeProfile{P} <: Profile
    p::P
end

function show(io::IO, ṗ::DerivativeProfile)
    print(io, "d/dt ($(ṗ.p))")
end

(ṗ::DerivativeProfile)(t) = ForwardDiff.derivative(ṗ.p, t)

"""
    d_dt(p::Profile)

Take the time derivative of `p` and return it as a new profile.

# Example

```jldoctest
julia> s = RigidBodyMotions.Sinusoid(π)
Sinusoid (ω = 3.14)

julia> s.([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 0.0
 1.0
 0.7071067811865476

julia> c = RigidBodyMotions.d_dt(s)
d/dt (Sinusoid (ω = 3.14))

julia> c.([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
  3.141592653589793
  1.9236706937217898e-16
 -2.221441469079183

```
"""
d_dt(p::Profile) = DerivativeProfile(p)

struct ScaledProfile{N <: Real, P <: Profile} <: Profile
    s::N
    p::P
end
function show(io::IO, p::ScaledProfile)
    print(io, "$(p.s) × ($(p.p))")
end

"""
    s::Number * p::Profile

Returns a scaled profile with `(s*p)(t) = s*p(t)`

# Example

```jldoctest
julia> s = RigidBodyMotions.Sinusoid(π)
Sinusoid (ω = 3.14)

julia> 2s
2 × (Sinusoid (ω = 3.14))

julia> (2s).([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 0.0
 2.0
 1.4142135623730951

```
"""
s::Number * p::Profile = ScaledProfile(s, p)

"""
    -(p₁::Profile, p₂::Profile)

```jldoctest
julia> s = RigidBodyMotions.Sinusoid(π)
Sinusoid (ω = 3.14)

julia> 2s
2 × (Sinusoid (ω = 3.14))

julia> (2s).([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 0.0
 2.0
 1.4142135623730951

julia> s = RigidBodyMotions.Sinusoid(π);

julia> s.([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 0.0
 1.0
 0.7071067811865476

julia> (-s).([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 -0.0
 -1.0
 -0.7071067811865476

julia> (s - s).([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 0.0
 0.0
 0.0
```
"""
-(p::Profile) = ScaledProfile(-1, p)
(p::ScaledProfile)(t) = p.s*p.p(t)

struct ShiftedProfile{N <: Real, P <: Profile} <: Profile
    Δt::N
    p::P
end
function show(io::IO, p::ShiftedProfile)
    print(io, "$(p.p) >> $(p.Δt)")
end

(p::ShiftedProfile)(t) = p.p(t - p.Δt)

"""
    p::Profile >> Δt::Number

Shift the profile in time so that `(p >> Δt)(t) = p(t - Δt)`

# Example

```jldoctest
julia> s = RigidBodyMotions.Sinusoid(π);

julia> s >> 0.5
Sinusoid (ω = 3.14) >> 0.5

julia> (s >> 0.5).([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
 -1.0
  0.0
  0.7071067811865475

julia> (s << 0.5).([0.0, 0.5, 0.75])
3-element Array{Float64,1}:
  1.0
  1.2246467991473532e-16
 -0.7071067811865475

```
"""
p::Profile >> Δt::Number = ShiftedProfile(Δt, p)
p::Profile << Δt::Number = ShiftedProfile(-Δt, p)

struct AddedProfiles{T <: Tuple} <: Profile
    ps::T
end
function show(io::IO, Σp::AddedProfiles)
    println(io, "AddedProfiles:")
    for p in Σp.ps
        println(io, "  $p")
    end
end

"""
    p₁::Profile + p₂::Profile

Add the profiles so that `(p₁ + p₂)(t) = p₁(t) + p₂(t)`.

# Examples

```jldoctest
julia> ramp₁ = RigidBodyMotions.EldredgeRamp(5)
logcosh ramp (aₛ = 5.0)

julia> ramp₂ = RigidBodyMotions.ColoniusRamp(5)
power series ramp (n = 5.0)

julia> ramp₁ + ramp₂
AddedProfiles:
  logcosh ramp (aₛ = 5.0)
  power series ramp (n = 5.0)


julia> ramp₁ + (ramp₂ + ramp₁) == ramp₁ + ramp₂ + ramp₁
true

```
"""
+(p::Profile, Σp::AddedProfiles) = AddedProfiles((p, Σp.ps...))
+(Σp::AddedProfiles, p::Profile) = AddedProfiles((Σp.ps..., p))
function +(Σp₁::AddedProfiles, Σp₂::AddedProfiles)
    AddedProfiles((Σp₁..., Σp₂...))
end

-(p₁::Profile, p₂::Profile) = p₁ + (-p₂)

+(p::Profile...) = AddedProfiles(p)

function (Σp::AddedProfiles)(t)
    f = 0.0
    for p in Σp.ps
        f += p(t)
    end
    f
end

struct Sinusoid <: Profile
    ω::Float64
end
(s::Sinusoid)(t) = sin(s.ω*t)
show(io::IO, s::Sinusoid) = print(io, "Sinusoid (ω = $(round(s.ω, digits=2)))")

struct EldredgeRamp <: Profile
    aₛ::Float64
end
(r::EldredgeRamp)(t) = 0.5(log(2cosh(r.aₛ*t)) + r.aₛ*t)/r.aₛ
show(io::IO, r::EldredgeRamp) = print(io, "logcosh ramp (aₛ = $(round(r.aₛ, digits=2)))")

struct ColoniusRamp <: Profile
    n::Int
end
function (r::ColoniusRamp)(t)
    Δt = t + 0.5
    if Δt ≤ 0
        0.0
    elseif Δt ≥ 1
        Δt - 0.5
    else
        f = 0.0
        for j = 0:r.n
            f += binomial(r.n + j, j)*(r.n - j + 1)*(1 - Δt)^j
        end
        f*Δt^(r.n + 2)/(2r.n + 2)
    end
end
show(io::IO, r::ColoniusRamp) = print(io, "power series ramp (n = $(round(r.n, digits=2)))")

end
