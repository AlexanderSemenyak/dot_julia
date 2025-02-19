"""
    BoolDistribution(p_true)

Create a distribution over Boolean values (`true` or `false`).

`p_true` is the probability of the `true` outcome; the probability of `false` is 1-`p_true`.
"""
struct BoolDistribution
    p::Float64 # probability of true
end

pdf(d::BoolDistribution, s::Bool) = s ? d.p : 1.0-d.p

rand(rng::AbstractRNG, d::BoolDistribution) = rand(rng) <= d.p

Base.iterate(d::BoolDistribution) = ((d.p, true), true)
function Base.iterate(d::BoolDistribution, state::Bool)
    if state
        return  ((1.0 - d.p, false), false)
    else
        return nothing
    end
end    

support(d::BoolDistribution) = [true, false]

==(d1::BoolDistribution, d2::BoolDistribution) = d1.p == d2.p

Base.hash(d::BoolDistribution) = hash(d.p)

Base.length(d::BoolDistribution) = 2

Base.show(io::IO, m::MIME"text/plain", d::BoolDistribution) = showdistribution(io, m, d, title="BoolDistribution")
