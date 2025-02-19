export upperbound, lowerbound

function upperbound(a, b::Curve{D}, β::Interval) where {D}
    evalpt = b(mid(β))
    return minimum_distance(a, evalpt, @SVector(ones(D)))
end

function upperbound(a::Curve, b::Curve, α::Interval, β::Interval)
    norm(a(mid(α)) - b(mid(β)))
end

function lowerbound(a, b::Curve{D}, β::Interval) where {D}
    approx = cvxhull(b, β)
    return minimum_distance(a, approx, @SVector(ones(D)))
end

function lowerbound(a::Curve{D}, b::Curve{D}, α::Interval, β::Interval) where {D}
    bapprox = cvxhull(b, β)
    aapprox = cvxhull(a, α)
    return minimum_distance(aapprox, bapprox, @SVector(ones(D)))
end

function getbounds(a, b, θ...)
    lb = lowerbound(a, b, θ...)
    ub = upperbound(a, b, θ...)
    return lb, ub
end

import ConvexBodyProximityQueries: support
support(pt::SVector{D, T}, dir::SVector{D, T}) where {D, N, T} = pt
function support(vertices::SVector{N, SVector{D, T}}, dir::SVector{D, T}) where {D, N, T}
    @inbounds vertices[argmax(Ref(dir').*vertices)]
end

function cvxhull(b::Curve{2, T}, β::Interval) where {T}
    fA = b(β.lo)
    fB = b(β.hi)
    center = (fA + fB)/2.0
    fdist = norm(fA - fB)
    rotate = SMatrix{2,2}(1.0I)
    if fdist > 0.0
        dir = (fB-fA)/fdist
        rotate = SMatrix{2,2}(dir[1],dir[2],-dir[2],dir[1])
    end
    a = arclength(b, β)/2.0
    if (a - fdist/2.0) > eps(T)
        b = sqrt(a^2 - (fdist/2)^2)
        octagon = SVector{8}(
                   SVector{2}(a*(√2 - 1), b),
                   SVector{2}(a, b*(√2 - 1)),
                   SVector{2}(a, -b*(√2 - 1)),
                   SVector{2}(a*(√2 - 1), -b),
                   SVector{2}(-a*(√2 - 1), -b),
                   SVector{2}(-a, -b*(√2 - 1)),
                   SVector{2}(-a, b*(√2 - 1)),
                   SVector{2}(-a*(√2 - 1), b),
                  )
        vertices = Ref(rotate).*octagon .+ Ref(center)
    else
        vertices = SVector{2}(fA, fB)
    end
end

function cvxhull(b::Curve{3, T}, β::Interval) where {T}
    fA = b(β.lo)
    fB = b(β.hi)
    center = (fA + fB)/2.0
    fdist = norm(fA - fB)
    rotate = SMatrix{3,3}(1.0I)
    if fdist > 0.0
        dir = (fB-fA)/fdist
        aux = SVector{3}(1.0, 0.0, 0.0)
        aux = abs(dir'*aux) < 0.99 ? aux : SVector{3}(0.0, 1.0, 0.0)
        auxperp = normalize(aux × dir)
        rotate = hcat(dir, aux, auxperp)
    end
    a = arclength(b, β)/2.0
    if (a - fdist/2.0) > eps(T)
        b = sqrt(a^2 - (fdist/2)^2)
        tetradecahedron = SVector{16}(
                   SVector{3}( a,  b*(√2 - 1),  b*(√2 - 1)),
                   SVector{3}( a, -b*(√2 - 1),  b*(√2 - 1)),
                   SVector{3}( a, -b*(√2 - 1), -b*(√2 - 1)),
                   SVector{3}( a,  b*(√2 - 1), -b*(√2 - 1)),
                   SVector{3}( a*(√2 - 1),  b,  b),
                   SVector{3}( a*(√2 - 1), -b,  b),
                   SVector{3}( a*(√2 - 1), -b, -b),
                   SVector{3}( a*(√2 - 1),  b, -b),
                   SVector{3}(-a*(√2 - 1),  b,  b),
                   SVector{3}(-a*(√2 - 1), -b,  b),
                   SVector{3}(-a*(√2 - 1), -b, -b),
                   SVector{3}(-a*(√2 - 1),  b, -b),
                   SVector{3}(-a,  b*(√2 - 1),  b*(√2 - 1)),
                   SVector{3}(-a, -b*(√2 - 1),  b*(√2 - 1)),
                   SVector{3}(-a, -b*(√2 - 1), -b*(√2 - 1)),
                   SVector{3}(-a,  b*(√2 - 1), -b*(√2 - 1)),
                  )
        vertices = Ref(rotate).*tetradecahedron .+ Ref(center)
    else
        vertices = SVector{2}(fA, fB)
    end
end
