export elem_in_algebra

parent_type(::Type{AlgAssAbsOrdElem{S, T}}) where {S, T} = AlgAssAbsOrd{S, T}

parent_type(::AlgAssAbsOrdElem{S, T}) where {S, T} = AlgAssAbsOrd{S, T}

@doc Markdown.doc"""
    parent(x::AlgAssAbsOrdElem) -> AlgAssAbsOrd

> Returns the order containing $x$.
"""
@inline parent(x::AlgAssAbsOrdElem) = x.parent

################################################################################
#
#  Parent check
#
################################################################################

function check_parent(x::AlgAssAbsOrdElem{S, T}, y::AlgAssAbsOrdElem{S, T}) where {S, T}
  return parent(x) === parent(y)
end

################################################################################
#
#  Parent object overloading
#
################################################################################

(O::AlgAssAbsOrd{S, T})(a::T, check::Bool = true) where {S, T} = begin
  if check
    (x, y) = _check_elem_in_order(a, O)
    !x && error("Algebra element not in the order")
    return AlgAssAbsOrdElem{S, T}(O, deepcopy(a), y)
  else
    return AlgAssAbsOrdElem{S, T}(O, deepcopy(a))
  end
end

(O::AlgAssAbsOrd{S, T})(a::T, arr::Vector{fmpz}, check::Bool = false) where {S, T} = begin
  if check
    (x, y) = _check_elem_in_order(a, O)
    (!x || arr != y) && error("Algebra element not in the order")
    return AlgAssAbsOrdElem{S, T}(O, deepcopy(a), y)
  else
    return AlgAssAbsOrdElem{S, T}(O, deepcopy(a), deepcopy(arr))
  end
end

(O::AlgAssAbsOrd{S, T})(arr::Vector{fmpz}) where {S, T} = begin
  M = basis_mat(O, copy = false)
  N = matrix(FlintZZ, 1, degree(O), arr)
  NM = N*M
  x = elem_from_mat_row(algebra(O), NM.num, 1, NM.den)
  return AlgAssAbsOrdElem{S, T}(O, x, deepcopy(arr))
end

(O::AlgAssAbsOrd{S, T})(a::AlgAssAbsOrdElem{S, T}, check::Bool = true) where {S, T} = begin
  b = elem_in_algebra(a) # already a copy
  if check
    (x, y) = _check_elem_in_order(b, O)
    !x && error("Algebra element not in the order")
    return AlgAssAbsOrdElem{S, T}(O, b, y)
  else
    return AlgAssAbsOrdElem{S, T}(O, b)
  end
end

(O::AlgAssAbsOrd)(a::T, check::Bool = true) where T = O(algebra(O)(a), check)

################################################################################
#
#  Deepcopy
#
################################################################################

function Base.deepcopy_internal(a::AlgAssAbsOrdElem, dict::IdDict)
  b = parent(a)()
  b.elem_in_algebra = Base.deepcopy_internal(a.elem_in_algebra, dict)
  if a.has_coord
    b.has_coord = true
    b.coordinates = Base.deepcopy_internal(a.coordinates, dict)
  end
  return b
end

################################################################################
#
#  Special elements
#
################################################################################

(O::AlgAssAbsOrd{S, T})() where {S, T} = AlgAssAbsOrdElem{S, T}(O)

one(O::AlgAssAbsOrd) = O(one(algebra(O)))

zero(O::AlgAssAbsOrd) = O(algebra(O)())

################################################################################
#
#  Element in algebra
#
################################################################################

@doc Markdown.doc"""
    elem_in_algebra(x::AlgAssAbsOrdElem; copy::Bool = true) -> AbsAlgAssElem
    elem_in_algebra(x::AlgAssRelOrdElem; copy::Bool = true) -> AbsAlgAssElem

> Returns $x$ as an element of the algebra containing it.
"""
function elem_in_algebra(x::Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem }; copy::Bool = true) where T
  if copy
    return deepcopy(x.elem_in_algebra)
  else
    return x.elem_in_algebra
  end
end

_elem_in_algebra(x::Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem }; copy::Bool = true) = elem_in_algebra(x, copy = copy)

################################################################################
#
#  "Assure" functions for fields
#
################################################################################

function assure_has_coord(x::Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem })
  if x.has_coord
    return nothing
  end

  a, b = _check_elem_in_order(elem_in_algebra(x, copy = false), parent(x))
  !a && error("Not a valid order element")
  x.coordinates = b
  x.has_coord = true
  return nothing
end

################################################################################
#
#  Coordinates
#
################################################################################

@doc Markdown.doc"""
    coordinates(x::AlgAssAbsOrdElem; copy::Bool = true) -> Vector{fmpz}
    coordinates(x::AlgAssRelOrdElem; copy::Bool = true) -> Vector{NumFieldElem}

> Returns the coordinates of $x$ in the basis of `parent(x)`.
"""
function coordinates(x::Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem }; copy::Bool = true)
  assure_has_coord(x)
  if copy
    return deepcopy(x.coordinates)
  else
    return x.coordinates
  end
end

################################################################################
#
#  Unary operations
#
################################################################################

@doc Markdown.doc"""
    -(x::AlgAssAbsOrdElem) -> AlgAssAbsOrdElem
    -(x::AlgAssRelOrdElem) -> AlgAssRelOrdElem

> Returns $-x$.
"""
function -(x::Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem })
  return parent(x)(-elem_in_algebra(x, copy = false))
end

###############################################################################
#
#  Binary operations
#
###############################################################################

@doc Markdown.doc"""
    *(x::AlgAssAbsOrdElem, y::AlgAssAbsOrdElem) -> AlgAssAbsOrdElem
    *(x::AlgAssRelOrdElem, y::AlgAssRelOrdElem) -> AlgAssRelOrdElem

> Return $x \cdot y$.
"""
function *(x::T, y::T) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  !check_parent(x, y) && error("Wrong parents")
  return parent(x)(elem_in_algebra(x, copy = false)*elem_in_algebra(y, copy = false))
end

@doc Markdown.doc"""
    +(x::AlgAssAbsOrdElem, y::AlgAssAbsOrdElem) -> AlgAssAbsOrdElem
    +(x::AlgAssRelOrdElem, y::AlgAssRelOrdElem) -> AlgAssRelOrdElem

> Return $x + y$.
"""
function +(x::T, y::T) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  !check_parent(x, y) && error("Wrong parents")
  z = parent(x)(elem_in_algebra(x, copy = false) + elem_in_algebra(y, copy = false))
  if x.has_coord && y.has_coord
    z.coordinates = [ x.coordinates[i] + y.coordinates[i] for i = 1:degree(parent(x)) ]
    z.has_coord = true
  end
  return z
end

@doc Markdown.doc"""
    -(x::AlgAssAbsOrdElem, y::AlgAssAbsOrdElem) -> AlgAssAbsOrdElem
    -(x::AlgAssRelOrdElem, y::AlgAssRelOrdElem) -> AlgAssRelOrdElem

> Return $x - y$.
"""
function -(x::T, y::T) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  !check_parent(x, y) && error("Wrong parents")
  z = parent(x)(elem_in_algebra(x, copy = false) - elem_in_algebra(y, copy = false))
  if x.has_coord && y.has_coord
    z.coordinates = [ x.coordinates[i] - y.coordinates[i] for i = 1:degree(parent(x)) ]
    z.has_coord = true
  end
  return z
end

function *(n::Union{Integer, fmpz}, x::AlgAssAbsOrdElem)
  O=x.parent
  y=Array{fmpz,1}(undef, O.dim)
  z=coordinates(x, copy = false)
  for i=1:O.dim
    y[i] = z[i] * n
  end
  return O(y)
end

*(x::AlgAssAbsOrdElem, n::Union{Integer, fmpz}) = n*x

# Computes a/b if action is :right and b\a if action is :left (and if this is possible)
function divexact(a::T, b::T, action::Symbol, check::Bool = true) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  !check_parent(a, b) && error("Wrong parents")
  O = parent(a)
  c = divexact(elem_in_algebra(a, copy = false), elem_in_algebra(b, copy = false), action)
  if check
    (x, y) = _check_elem_in_order(c, O)
    !x && error("Quotient not an element of the order")
    return typeof(a)(O, c, y) # Avoid unneccessary copies
  end
  return typeof(a)(O, c)
end

@doc Markdown.doc"""
    divexact_right(a::AlgAssAbsOrdElem, b::AlgAssAbsOrdElem, check::Bool = true)
    divexact_right(a::AlgAssRelOrdElem, b::AlgAssRelOrdElem, check::Bool = true)
      -> AlgAssRelOrdElem

> Returns an element $c \in O$ such that $a = c \cdot b$ where $O$ is the order
> containing $a$.
> If `check` is `false` it is not checked whether $c$ is an element of $O$.
"""
divexact_right(a::T, b::T, check::Bool = true) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } } = divexact(a, b, :right, check)

@doc Markdown.doc"""
    divexact_left(a::AlgAssAbsOrdElem, b::AlgAssAbsOrdElem, check::Bool = true)
    divexact_left(a::AlgAssRelOrdElem, b::AlgAssRelOrdElem, check::Bool = true)
      -> AlgAssRelOrdElem

> Returns an element $c \in O$ such that $a = b \cdot c$ where $O$ is the order
> containing $a$.
> If `check` is `false` it is not checked whether $c$ is an element of $O$.
"""
divexact_left(a::T, b::T, check::Bool = true) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } } = divexact(a, b, :left, check)

################################################################################
#
#  Conversion from matrix
#
################################################################################

function elem_from_mat_row(O::AlgAssAbsOrd, M::fmpz_mat, i::Int)
  return O(fmpz[ M[i, j] for j = 1:degree(O) ])
end

function elem_to_mat_row!(M::fmpz_mat, i::Int, a::AlgAssAbsOrdElem)
  for c = 1:ncols(M)
    M[i, c] = deepcopy(coordinates(a; copy = false))[c]
  end
  return nothing
end

################################################################################
#
#  Exponentiation
#
################################################################################

@doc Markdown.doc"""
    ^(x::AlgAssAbsOrdElem, y::Union{ Int, fmpz }) -> AlgAssAbsOrdElem
    ^(x::AlgAssRelOrdElem, y::Union{ Int, fmpz }) -> AlgAssRelOrdElem

> Returns $x^y$.
"""
function ^(x::Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem }, y::Union{fmpz, Int})
  z = parent(x)()
  z.elem_in_algebra = elem_in_algebra(x, copy = false)^y
  return z
end

################################################################################
#
#  Equality
#
################################################################################

@doc Markdown.doc"""
    ==(a::AlgAssAbsOrdElem, b::AlgAssAbsOrdElem) -> Bool
    ==(a::AlgAssRelOrdElem, b::AlgAssRelOrdElem) -> Bool

> Returns `true` if $a$ and $b$ are equal and `false` otherwise.
"""
function ==(a::T, b::T) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  if parent(a) !== parent(b)
    return false
  end
  return elem_in_algebra(a, copy = false) == elem_in_algebra(b, copy = false)
end

################################################################################
#
#  Unsafe operations
#
################################################################################

function add!(z::T, x::T, y::T) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  z.elem_in_algebra = add!(elem_in_algebra(z, copy = false), elem_in_algebra(x, copy = false), elem_in_algebra(y, copy = false))
  z.has_coord = false
  return z
end

function mul!(z::T, x::T, y::T) where { T <: Union{ AlgAssAbsOrdElem, AlgAssRelOrdElem } }
  z.elem_in_algebra = mul!(elem_in_algebra(z, copy = false), elem_in_algebra(x, copy = false), elem_in_algebra(y, copy = false))
  z.has_coord = false
  return z
end

function mul!(z::AlgAssAbsOrdElem, x::Union{ Int, fmpz }, y::AlgAssAbsOrdElem)
  z.elem_in_algebra = mul!(elem_in_algebra(z, copy = false), x, elem_in_algebra(y, copy = false))
  if z.has_coord && y.has_coord
    x = fmpz(x)
    for i = 1:degree(parent(y))
      z.coordinates[i] = mul!(z.coordinates[i], x, coordinates(y, copy = false)[i])
    end
  end
  return z
end

mul!(z::AlgAssAbsOrdElem, y::AlgAssAbsOrdElem, x::Union{ Int, fmpz }) = mul!(z, x, y)

################################################################################
#
#  String I/O
#
################################################################################

function show(io::IO, a::AlgAssAbsOrdElem)
  print(io, a.elem_in_algebra)
end

################################################################################
#
#  Representation matrices
#
################################################################################

@doc Markdown.doc"""
    representation_matrix(x::AlgAssAbsOrdElem, action::Symbol = :left) -> fmpz_mat

> Returns a matrix representing multiplication with $x$ with respect to the basis
> of `order(x)`.
> The multiplication is from the left if `action == :left` and from the right if
> `action == :right`.
"""
function representation_matrix(x::AlgAssAbsOrdElem, action::Symbol = :left)

  O = parent(x)
  M = basis_mat(O, copy = false)
  M1 = basis_mat_inv(O, copy = false)

  B = FakeFmpqMat(representation_matrix(elem_in_algebra(x, copy = false), action))
  B = mul!(B, M, B)
  B = mul!(B, B, M1)

  @assert B.den == 1
  return B.num
end

################################################################################
#
#  Trace
#
################################################################################

@doc Markdown.doc"""
    tr(x::AlgAssAbsOrdElem) -> fmpz

> Returns the trace of $x$.
"""
function tr(x::AlgAssAbsOrdElem)
  return FlintZZ(tr(x.elem_in_algebra))
end

@doc Markdown.doc"""
    trred(x::AlgAssAbsOrdElem) -> fmpz

> Returns the reduced trace of $x$.
"""
function trred(x::AlgAssAbsOrdElem)
  return FlintZZ(trred(x.elem_in_algebra))
end

################################################################################
#
#  Modular exponentiation and division
#
################################################################################

@doc Markdown.doc"""
    powermod(a::AlgAssAbsOrdElem, i::Union{ fmpz, Int }, m::AlgAssAbsOrdIdl) -> AlgAssAbsOrdElem

> Returns an element $b$ of `order(a)` such that $a^i \equiv b \mod m$.
"""
function powermod(a::AlgAssAbsOrdElem, i::Union{fmpz, Int}, m::AlgAssAbsOrdIdl)
  if i < 0
    b, a = isdivisible_mod_ideal(one(parent(a)), a, m)
    @assert b "Element is not invertible modulo the ideal"
    return powermod(a, -i, m)
  end

  if i == 0
    return one(parent(a))
  end

  if i == 1
    b = mod(a, m)
    return b
  end

  if mod(i, 2) == 0
    j = div(i, 2)
    b = powermod(a, j, m)
    b = b^2
    b = mod(b, m)
    return b
  end

  b = mod(a*powermod(a, i - 1, m), m)
  return b
end

# This is mostly isdivisible in NfOrd/ResidueRing.jl
function isdivisible_mod_ideal(x::AlgAssAbsOrdElem, y::AlgAssAbsOrdElem, a::AlgAssAbsOrdIdl)

  iszero(y) && error("Dividing by zero")

  if iszero(x)
    return true, zero(parent(x))
  end

  O = parent(x)
  d = degree(O)
  V = zero_matrix(FlintZZ, 2*d + 1, 2*d + 1)
  V[1, 1] = fmpz(1)

  for i = 1:d
    V[1, 1 + i] = coordinates(x, copy = false)[i]
  end

  A = representation_matrix(y)
  B = basis_mat(a, copy = false)

  _copy_matrix_into_matrix(V, 2, 2, A)
  _copy_matrix_into_matrix(V, 2 + d, 2, B)

  for i = 1:d
    V[1 + i, d + 1 + i] = 1
  end

  V = hnf(V)

  for i = 2:(d + 1)
    if !iszero(V[1, i])
      return false, O()
    end
  end

  z = -O([ V[1, i] for i = (d + 2):(2*d + 1) ])
  return true, z
end

################################################################################
#
#  isone/iszero
#
################################################################################

iszero(a::AlgAssAbsOrdElem) = iszero(elem_in_algebra(a, copy = false))

isone(a::AlgAssAbsOrdElem) = isone(elem_in_algebra(a, copy = false))
