export subalgebra, decompose

_base_ring(A::AbsAlgAss) = base_ring(A)

################################################################################
#
#  Morphism types
#
################################################################################

morphism_type(::Type{T}, ::Type{S}) where {R, T <: AbsAlgAss{R}, S <: AbsAlgAss{R}} = AbsAlgAssMor{T, S, Generic.MatSpaceElem{R}}

morphism_type(::Type{T}, ::Type{S}) where {R, T <: AbsAlgAss{fmpq}, S <: AbsAlgAss{fmpq}} = AbsAlgAssMor{T, S, fmpq_mat}

morphism_type(::Type{T}, ::Type{S}) where {R, T <: AbsAlgAss{fq}, S <: AbsAlgAss{fq}} = AbsAlgAssMor{T, S, fq_mat}

morphism_type(::Type{T}, ::Type{S}) where {R, T <: AbsAlgAss{fq_nmod}, S <: AbsAlgAss{fq_nmod}} = AbsAlgAssMor{T, S, fq_nmod_mat}

morphism_type(::Type{T}, ::Type{S}) where {R, T <: AbsAlgAss{nmod}, S <: AbsAlgAss{nmod}} = AbsAlgAssMor{T, S, nmod_mat}

morphism_type(::Type{T}, ::Type{S}) where {R, T <: AbsAlgAss{gfp_elem}, S <: AbsAlgAss{gfp_elem}} = AbsAlgAssMor{T, S, gfp_mat}

morphism_type(A::Type{T}) where {T <: AbsAlgAss} = morphism_type(A, A)

################################################################################
#
#  Basis
#
################################################################################

@doc Markdown.doc"""
    basis(A::AbsAlgAss) -> Vector{AbsAlgAssElem}

> Returns the basis of $A$.
"""
function basis(A::AbsAlgAss)
  if isdefined(A, :basis)
    return A.basis::Vector{elem_type(A)}
  end
  B = Vector{elem_type(A)}(undef, dim(A))
  for i in 1:dim(A)
    z = Vector{elem_type(base_ring(A))}(undef, dim(A))
    for j in 1:dim(A)
      z[j] = zero(base_ring(A))
    end
    z[i] = one(base_ring(A))
    B[i] = A(z)
  end
  A.basis = B
  return B
end

################################################################################
#
#  Predicates
#
################################################################################

issimple_known(A::AbsAlgAss) = A.issimple != 0

################################################################################
#
#  Associativity, Distributivity test
#
################################################################################

function check_associativity(A::AbsAlgAss)
  for i = 1:dim(A)
    for j = 1:dim(A)
      el = A[i] * A[j]
      for k = 1:dim(A)
        if el * A[k] != A[i] * (A[j] * A[k])
          return false
        end
      end
    end
  end
  return true
end

function check_distributivity(A::AbsAlgAss)
  for i = 1:dim(A)
    for j = 1:dim(A)
      el = A[i]*A[j]
      for k = 1:dim(A)
        if A[i] * (A[j] + A[k]) != el + A[i] * A[k]
          return false
        end
      end
    end
  end
  return true
end

################################################################################
#
#  Dimension of center
#
################################################################################

function dimension_of_center(A::AbsAlgAss)
  C, _ = center(A)
  return dim(C)
end

################################################################################
#
#  Subalgebras
#
################################################################################

# This is the generic fallback which constructs an associative algebra
@doc Markdown.doc"""
    subalgebra(A::AbsAlgAss, e::AbsAlgAssElem, idempotent::Bool = false,
               action::Symbol = :left)
      -> AlgAss, AbsAlgAssMor

> Given an algebra $A$ and an element $e$, this function constructs the algebra
> $e \cdot A$ (if `action == :left`) respectively $A \cdot e$ (if `action == :right`)
> and a map from this algebra to $A$.
> If `idempotent` is `true`, it is assumed that $e$ is idempotent in $A$.
"""
function subalgebra(A::AbsAlgAss{T}, e::AbsAlgAssElem{T}, idempotent::Bool = false, action::Symbol = :left) where {T}
  @assert parent(e) == A
  B, mB = AlgAss(A)
  C, mC = subalgebra(B, mB\e, idempotent, action)
  mD = compose_and_squash(mB, mC)
  @assert domain(mD) == C
  return C, mD
end

@doc Markdown.doc"""
    subalgebra(A::AbsAlgAss, basis::Vector{AbsAlgAssElem})
      -> AlgAss, AbsAlgAssMor

> Returns the subalgebra $A$ generated be the elements in `basis` and a map
> from this algebra to $A$.
"""
function subalgebra(A::AbsAlgAss{T}, basis::Vector{ <: AbsAlgAssElem{T} }) where T
  B, mB = AlgAss(A)
  basis_pre = elem_type(B)[mB\(basis[i]) for i in 1:length(basis)]
  C, mC = subalgebra(B, basis_pre)
  mD = compose_and_squash(mB, mC)
  @assert domain(mD) == C
  return C, mD
end

################################################################################
#
#  Decomposition
#
################################################################################

# Assume that A is a commutative algebra over a finite field of cardinality q.
# This functions computes a basis for ker(x -> x^q).
function kernel_of_frobenius(A::AbsAlgAss)
  F = base_ring(A)
  q = order(F)

  b = A()
  B = zero_matrix(F, dim(A), dim(A))
  for i = 1:dim(A)
    b.coeffs[i] = one(F)
    if i > 1
      b.coeffs[i - 1] = zero(F)
    end
    c = b^q - b
    for j = 1:dim(A)
      B[j, i] = c.coeffs[j]
    end
  end

  V = right_kernel_basis(B)
  return [ A(v) for v in V ]
end

@doc Markdown.doc"""
    decompose(A::AbsAlgAss) -> Array{Tuple{AlgAss, AbsAlgAssMor}}

> Given a semisimple algebra $A$ over a field, this function returns a
> decomposition of $A$ as a direct sum of simple algebras and maps from these
> components to $A$.
"""
function decompose(A::AlgAss{T}) where {T}
  if isdefined(A, :decomposition)
    return A.decomposition::Vector{Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}}
  end

  if issimple_known(A) && A.issimple == 1
    B, mB = AlgAss(A)
    return Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[(B, mB)]
  end

  res = _decompose(A)
  A.decomposition = res
  return res
end

# Generic function for everything besides AlgAss
function decompose(A::AbsAlgAss{T}) where T
  if isdefined(A, :decomposition)
    return A.decomposition::Vector{Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}}
  end

  B, mB = AlgAss(A)

  if issimple_known(A) && A.issimple == 1
    return Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[ (B, mB) ]
  end

  D = _decompose(B)
  res = Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[]
  for (S, mS) in D
    mD = compose_and_squash(mB, mS)
    push!(res, (S, mD))
  end
  A.decomposition = res
  return res
end

function _decompose(A::AbsAlgAss{T}) where {T}
  @assert _issemisimple(A) != 2 "Algebra is not semisimple"
  if iscommutative(A)
    return _dec_com(A)
  else
    return _dec_via_center(A)
  end
end

function _dec_via_center(A::S) where {T, S <: AbsAlgAss{T}}
  ZA, mZA = center(A)
  Algs = _dec_com(ZA)
  ZA.decomposition = Algs
  res = Tuple{AlgAss{T}, morphism_type(AlgAss{T}, S)}[ subalgebra(A, mZA(BtoZA(one(B))), true) for (B, BtoZA) in Algs]
  for i in 1:length(res)
    res[i][1].issimple = 1
    B, BtoZA = Algs[i] # B is the centre of res[i][1]
    # Build a map from B to res[i][1] via B -> ZA -> A -> res[i][1]
    M = zero_matrix(base_ring(A), dim(B), dim(res[i][1]))
    for j = 1:dim(B)
      t = mZA(BtoZA(B[j]))
      s = res[i][2]\t
      elem_to_mat_row!(M, j, s)
    end
    if dim(res[i][1]) != dim(B)
      res[i][1].center = (B, hom(B, res[i][1], M))
    else
      # res[i][1] is commutative, so we do not cache the centre
      iM = inv(M)
      BtoA = hom(B, A, M*res[i][2].mat, res[i][2].imat*iM)
      res[i] = (B, BtoA)
    end
  end
  A.decomposition = res
  return res
end

function _dec_com(A::AbsAlgAss)
  if characteristic(base_ring(A)) > 0
    return _dec_com_finite(A)
  else
    return _dec_com_gen(A)
  end
end

function _dec_com_gen(A::AbsAlgAss{T}) where {T <: FieldElem}
  if dim(A) == 1
    A.issimple = 1
    B, mB = AlgAss(A)
    return Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[(B, mB)]
  end

  F = base_ring(A)

  k = dim(A)

  V = elem_type(A)[A[i] for i in 1:k]

  while true
    c = elem_type(F)[ rand(F, -10:10) for i = 1:k ]
    a = dot(c, V)
    f = minpoly(a)

    if degree(f) < 2
      continue
    end
    if isirreducible(f)
      if degree(f) == dim(A)
        A.issimple = 1
        B, mB = AlgAss(A)
        return Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[(B, mB)]
      end
      continue
    end

    @assert issquarefree(f)

    fac = factor(f)
    R = parent(f)
    factors = Vector{elem_type(R)}()
    for ff in keys(fac.fac)
      push!(factors, ff)
    end
    sols = Vector{elem_type(R)}()
    right_side = elem_type(R)[ R() for i = 1:length(factors) ]
    max_deg = 0
    for i = 1:length(factors)
      right_side[i] = R(1)
      if i != 1
        right_side[i - 1] = R(0)
      end
      s = crt(right_side, factors)
      push!(sols, s)
      max_deg = max(max_deg, degree(s))
    end
    x = one(A)
    powers = Vector{elem_type(A)}()
    for i = 1:max_deg + 1
      push!(powers, x)
      x *= a
    end
    idems = Vector{elem_type(A)}()
    for s in sols
      idem = A()
      for i = 0:degree(s)
        idem += coeff(s, i)*powers[i + 1]
      end
      push!(idems, idem)
    end

    A.issimple = 2

    res = Vector{Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}}()
    for idem in idems
      S, StoA = subalgebra(A, idem, true)
      decS = _dec_com_gen(S)
      for (B, BtoS) in decS
        BtoA = compose_and_squash(StoA, BtoS)
        push!(res, (B, BtoA))
      end
    end
    return res
  end
end

function _dec_com_finite(A::AbsAlgAss{T}) where T
  if dim(A) == 1
    A.issimple = 1
    B, mB = AlgAss(A)
    return Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[(B, mB)]
  end

  F = base_ring(A)
  @assert !iszero(characteristic(F))
  V = kernel_of_frobenius(A)
  k = length(V)

  if k == 1
    A.issimple = 1
    B, mB = AlgAss(A)
    return Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}[(B, mB)]
  end
  
  A.issimple = 2
  c = elem_type(F)[ rand(F) for i = 1:k ]
  M = zero_matrix(F, dim(A), dim(A))
  a = dot(c, V)
  representation_matrix!(a, M)
  f = minpoly(M)
  while degree(f) < 2
    for i = 1:length(c)
      c[i] = rand(F)
    end
    a = dot(c, V)
    zero!(M)
    representation_matrix!(a, M)
    f = minpoly(M)
  end

  #@assert issquarefree(f)
  fac = factor(f)
  R = parent(f)
  factorss = collect(keys(fac.fac))
  sols = Vector{typeof(f)}(undef, length(factorss))
  right_side = typeof(f)[ zero(R) for i = 1:length(factorss) ]
  max_deg = 0
  for i = 1:length(factorss)
    right_side[i] = one(R)
    if 1 != i
      right_side[i - 1] = zero(R)
    end
    sols[i] = crt(right_side, factorss)
    max_deg = max(max_deg, degree(sols[i]))
  end
  powers = Vector{elem_type(A)}(undef, max_deg+1)
  powers[1] = one(A)
  powers[2] = a
  x = a
  for i = 3:max_deg + 1
    x *= a
    powers[i] = x
  end

  idems = Vector{elem_type(A)}()
  for s in sols
    idem = A()
    for i = 0:degree(s)
      idem += coeff(s, i)*powers[i + 1]
    end
    push!(idems, idem)
  end

  res = Vector{Tuple{AlgAss{T}, morphism_type(AlgAss{T}, typeof(A))}}()
  for idem in idems
    S, StoA = subalgebra(A, idem, true)
    decS = _dec_com_finite(S)
    for (B, BtoS) in decS
      BtoA = compose_and_squash(StoA, BtoS)
      push!(res, (B, BtoA))
    end
  end
  return res

end

################################################################################
#
#  Decomposition as number fields
#
################################################################################

@doc Markdown.doc"""
    as_number_fields(A::AbsAlgAss{fmpq})
      -> Vector{Tuple{AnticNumberField, AbsAlgAssToNfAbsMor}}

> Given a commutative algebra $A$ over $\mathbb Q$, this function returns a
> decomposition of $A$ as direct sum of number fields and maps from $A$ to
> these fields.
"""
function as_number_fields(A::AbsAlgAss{fmpq})
  if isdefined(A, :maps_to_numberfields)
    return A.maps_to_numberfields::Vector{Tuple{AnticNumberField, AbsAlgAssToNfAbsMor{typeof(A), elem_type(A)}}}
  end

  d = dim(A)

  Adec = decompose(A)

  fields_not_cached = false
  for i = 1:length(Adec)
    if !isdefined(Adec[i][1], :maps_to_numberfields)
      fields_not_cached = true
    end
  end

  if fields_not_cached
    # Compute a LLL reduced basis of the maximal order of A to find "small"
    # polynomials for the number fields.
    OA = maximal_order(A)
    L = lll(basis_mat(OA, copy = false).num)
    n = basis_mat(OA, copy = false).den
    basis_lll = [ elem_from_mat_row(A, L, i, n) for i = 1:d ]
  end

  M = zero_matrix(FlintQQ, 0, d)
  matrices = Vector{fmpq_mat}()
  fields = Vector{AnticNumberField}()
  for i = 1:length(Adec)
    # For each small algebra construct a number field and the isomorphism
    B, BtoA = Adec[i]
    dB = dim(B)
    if !isdefined(B, :maps_to_numberfields)
      local K, BtoK
      found_field = false # Only for debugging
      for j = 1:d
        t = BtoA\basis_lll[j]
        mint = minpoly(t)
        if degree(mint) == dB
          found_field = true
          K, BtoK = _as_field_with_isomorphism(B, t, mint)
          B.maps_to_numberfields = Tuple{AnticNumberField, AbsAlgAssToNfAbsMor{typeof(B), elem_type(B)}}[(K, BtoK)]
          push!(fields, K)
          break
        end
      end
      @assert found_field "This should not happen..."
    else
      K, BtoK = B.maps_to_numberfields[1]
      push!(fields, K)
    end

    if length(Adec) == 1
      A.maps_to_numberfields = Tuple{AnticNumberField, AbsAlgAssToNfAbsMor{typeof(A), elem_type(A)}}[(K, BtoK)]
      return A.maps_to_numberfields
    end

    # Construct the map from K to A
    N = zero_matrix(FlintQQ, degree(K), d)
    for j = 1:degree(K)
      t = BtoA(BtoK\basis(K)[j])
      elem_to_mat_row!(N, j, t)
    end
    push!(matrices, N)
    M = vcat(M, N)
  end
  @assert nrows(M) == d

  invM = inv(M)
  matrices2 = Vector{fmpq_mat}(undef, length(matrices))
  offset = 1
  for i = 1:length(matrices)
    r = nrows(matrices[i])
    N = sub(invM, 1:d, offset:(offset + r - 1))
    matrices2[i] = N
    offset += r
  end

  result = Vector{Tuple{AnticNumberField, AbsAlgAssToNfAbsMor{typeof(A), elem_type(A)}}}()
  for i = 1:length(fields)
    push!(result, (fields[i], AbsAlgAssToNfAbsMor(A, fields[i], matrices2[i], matrices[i])))
  end
  A.maps_to_numberfields = result
  return result
end

################################################################################
#
#  Random elements
#
################################################################################

function rand(A::AbsAlgAss{T}) where T
  c = T[rand(base_ring(A)) for i = 1:dim(A)]
  return A(c)
end

function rand(A::AbsAlgAss{T}, rng::UnitRange{Int}) where T
  c = T[rand(base_ring(A), rng) for i = 1:dim(A)]
  return A(c)
end

function rand(A::AlgAss{fmpq}, rng::UnitRange{Int} = -20:20)
  c = [fmpq(rand(FlintZZ, rng)) for i = 1:dim(A)]
  return A(c)
end

################################################################################
#
#  Generators
#
################################################################################

# Reduces the vector v w. r. t. M and writes it in the i-th row of M.
# M should look like this:
#     (0 1 * 0 *)
#     (1 0 * 0 *)
# M = (0 0 0 1 *)
#     (0 0 0 0 0)
#     (0 0 0 0 0),
# i. e. "almost" in rref, but the rows do not have to be sorted.
# For a column c of M pivot_rows[c] should be the row with the pivot or 0.
# The function changes M and pivot_rows in place!
function _add_row_to_rref!(M::MatElem{T}, v::Vector{T}, pivot_rows::Vector{Int}, i::Int) where { T <: FieldElem }
  @assert ncols(M) == length(v)
  @assert ncols(M) == length(pivot_rows)
  @assert 1 <= i && i <= nrows(M)

  for c = 1:ncols(M)
    M[i, c] = deepcopy(v[c])
  end

  rank_increases = false
  s = one(base_ring(M))
  for c = 1:ncols(M)
    if iszero(M[i, c])
      continue
    end

    r = pivot_rows[c]
    if r == 0
      if !rank_increases
        pivot_rows[c] = i
        rank_increases = true
        t = divexact(one(base_ring(M)), M[i, c])
        for j = (c + 1):ncols(M)
          M[i, j] = mul!(M[i, j], M[i, j], t)
        end
        M[i, c] = one(base_ring(M))

        for j = 1:nrows(M)
          if i == j
            continue
          end
          if iszero(M[j, c])
            continue
          end

          t = -M[j, c]
          for k = (c + 1):ncols(M)
            if iszero(M[i, k])
              continue
            end

            s = mul!(s, t, M[i, k])
            M[j, k] = add!(M[j, k], M[j, k], s)
          end
          M[j, c] = zero(base_ring(M))
        end
      end
      continue
    end

    t = -M[i, c] # we assume M[r, c] == 1 (M[r, c] is the pivot)
    for j = (c + 1):ncols(M)
      s = mul!(s, t, M[r, j])
      M[i, j] = add!(M[i, j], M[i, j], s)
    end
    M[i, c] = zero(base_ring(M))
  end

  return rank_increases
end

@doc Markdown.doc"""
    gens(A::AbsAlgAss, return_full_basis::Typel{Val{T}} = Val{false};
         thorough_search::Bool = false) where T
      -> Vector{AbsAlgAssElem}

> Returns a subset of `basis(A)`, which generates $A$ as an algebra over
> `base_ring(A)`.
> If `return_full_basis` is set to `Val{true}`, the function also returns a
> `Vector{AbsAlgAssElem}` containing a full basis consisting of monomials in
> the generators and a `Vector{Vector{Tuple{Int, Int}}}` containing the
> information on how these monomials are built. E. g.: If the function returns
> `g`, `full_basis` and `v`, then we have
> `full_basis[i] = prod( g[j]^k for (j, k) in v[i] )`.
> If `thorough_search` is `true`, the number of returned generators is possibly
> smaller. This will in general increase the runtime. It is not guaranteed that
> the number of generators is minimal in any case.
"""
function gens(A::AbsAlgAss, return_full_basis::Type{Val{T}} = Val{false}; thorough_search::Bool = false) where T
  d = dim(A)

  if thorough_search
    # Sort the basis by the degree of the minpolys (hopefully those with higher
    # degree generate a "bigger" subalgebra)
    minpoly_degrees = [ (i, degree(minpoly(A[i]))) for i = 1:d ]
    sort!(minpoly_degrees, by = x -> x[2], rev = true)
  else
    is_gen = falses(d)
  end

  generators = Vector{elem_type(A)}()
  full_basis = elem_type(A)[ one(A) ] # Contains products of generators which form a full basis
  elts_in_gens = Vector{Tuple{Int, Int}}[ Tuple{Int, Int}[] ]
  B = zero_matrix(base_ring(A), d, d)
  pivot_rows = zeros(Int, d)
  new_elements = Set{Int}()

  s = one(A)
  t = one(A)

  cur_dim = 0
  cur_basis_elt = 1
  while cur_dim != d
    if isempty(new_elements)
      # We have to add a generator
      new_gen = A()
      new_elt = false
      while true
        if thorough_search
          i = minpoly_degrees[cur_basis_elt][1]
        else
          i = rand(1:dim(A))
          while is_gen[i]
            i = rand(1:dim(A))
          end
          is_gen[i] = true
        end
        new_gen = A[i]
        cur_basis_elt += 1
        new_elt = _add_row_to_rref!(B, coeffs(new_gen, copy = false), pivot_rows, cur_dim + 1)
        if new_elt
          break
        end
      end
      push!(generators, new_gen)
      b = new_gen
      power = 1
      # Compute the powers of new_gen
      while new_elt
        cur_dim += 1
        push!(full_basis, b)
        if power == 1 && length(generators) != 1
          push!(new_elements, length(full_basis))
        end
        ind = Tuple{Int, Int}[ (length(generators), power) ]
        push!(elts_in_gens, ind)
        cur_dim == d ? break : nothing
        b *= new_gen
        power += 1
        new_elt = _add_row_to_rref!(B, coeffs(b, copy = false), pivot_rows, cur_dim + 1)
      end
      continue
    else
      i = pop!(new_elements)
      b = full_basis[i]
    end

    # Compute all possible productes involving b
    n = length(full_basis)
    for r = 1:n
      s = mul!(s, b, full_basis[r])
      for l = 1:n
        if !iscommutative(A)
          t = mul!(t, full_basis[l], s)
        else
          t = s
        end
        new_elt = _add_row_to_rref!(B, coeffs(t, copy = false), pivot_rows, cur_dim + 1)
        if !new_elt
          continue
        end
        push!(full_basis, deepcopy(t))
        cur_dim += 1
        coord = _merge_elts_in_gens!(elts_in_gens[l], deepcopy(elts_in_gens[i]), elts_in_gens[r])
        push!(elts_in_gens, coord)
        if thorough_search && coord[1][2] == 1 && coord[end][2] == 1
          push!(new_elements, length(full_basis))
        end
        if iscommutative(A)
          break
        end
        cur_dim == d ? break : nothing
      end
      cur_dim == d ? break : nothing
    end
  end

  # Remove the one
  popfirst!(full_basis)
  popfirst!(elts_in_gens)

  if return_full_basis == Val{true}
    return generators, full_basis, elts_in_gens
  else
    return generators
  end
end

################################################################################
#
#  Primitive elements
#
################################################################################

function primitive_element(A::AbsAlgAss)
  a, _ = _primitive_element(A)
  return a
end

function primitive_element(A::AbsAlgAss{fmpq})
  if isdefined(A, :maps_to_numberfields)
    return primitive_element_via_number_fields(A)
  end
  a, _ = _primitive_element(A)
  return a
end

function _primitive_element(A::AbsAlgAss)
  error("Not implemented yet")
  return nothing
end

function _primitive_element(A::AbsAlgAss{T}) where T <: Union{nmod, fq, fq_nmod, Generic.Res{fmpz}, fmpq, Generic.ResF{fmpz}, gfp_elem}
  d = dim(A)
  a = rand(A)
  f = minpoly(a)
  while degree(f) < d
    a = rand(A)
    f = minpoly(a)
  end
  return a, f
end

function primitive_element_via_number_fields(A::AbsAlgAss{fmpq})
  fields_and_maps = as_number_fields(A)
  a = A()
  for (K, AtoK) in fields_and_maps
    a += AtoK\gen(K)
  end
  return a
end

function _as_field(A::AbsAlgAss{T}) where T
  d = dim(A)
  a, mina = _primitive_element(A)
  b = one(A)
  M = zero_matrix(base_ring(A), d, d)
  elem_to_mat_row!(M, 1, b)
  for i in 1:(d - 1)
    b = mul!(b, b, a)
    elem_to_mat_row!(M, i + 1, b)
  end
  B = inv(M)
  N = zero_matrix(base_ring(A), 1, d)
  local f
  let N = N, B = B
    f = function(x)
      for i in 1:d
        N[1, i] = x.coeffs[i]
      end
      return N * B
    end
  end
  return a, mina, f
end

function _as_field_with_isomorphism(A::AbsAlgAss{S}) where { S <: Union{fmpq, gfp_elem, Generic.ResF{fmpz}, fq_nmod, fq} }
  return _as_field_with_isomorphism(A, _primitive_element(A)...)
end

# Assuming a is a primitive element of A and mina its minimal polynomial, this
# functions constructs the field base_ring(A)/mina and the isomorphism between
# A and this field.
function _as_field_with_isomorphism(A::AbsAlgAss{S}, a::AbsAlgAssElem{S}, mina::T) where { S <: Union{fmpq, gfp_elem, Generic.ResF{fmpz}, fq_nmod, fq}, T <: Union{fmpq_poly, gfp_poly, gfp_fmpz_poly, fq_nmod_poly, fq_poly} }
  s = one(A)
  M = zero_matrix(base_ring(A), dim(A), dim(A))
  elem_to_mat_row!(M, 1, s)
  for i = 2:dim(A)
    s = mul!(s, s, a)
    elem_to_mat_row!(M, i, s)
  end

  return __as_field_with_isomorphism(A, mina, M)
end

function __as_field_with_isomorphism(A::AbsAlgAss{fmpq}, f::fmpq_poly, M::fmpq_mat)
  K = number_field(f, cached = false)[1]
  return K, AbsAlgAssToNfAbsMor(A, K, inv(M), M)
end

function __as_field_with_isomorphism(A::AbsAlgAss{gfp_elem}, f::gfp_poly, M::gfp_mat)
  Fq = FqNmodFiniteField(f, Symbol("a"), false)
  return Fq, AbsAlgAssToFqMor(A, Fq, inv(M), M, parent(f))
end

function __as_field_with_isomorphism(A::AbsAlgAss{Generic.ResF{fmpz}}, f::gfp_fmpz_poly, M::Generic.MatSpaceElem{Generic.ResF{fmpz}})
  Fq = FqFiniteField(f, Symbol("a"), false)
  return Fq, AbsAlgAssToFqMor(A, Fq, inv(M), M, parent(f))
end

function __as_field_with_isomorphism(A::AbsAlgAss{S}, f::T, M::U) where { S <: Union{ fq_nmod, fq }, T <: Union{ fq_nmod_poly, fq_poly }, U <: Union{ fq_nmod_mat, fq_mat } }
  Fr, RtoFr = field_extension(f)
  return Fr, AbsAlgAssToFqMor(A, Fr, inv(M), M, parent(f), RtoFr)
end

################################################################################
#
#  Regular matrix algebra
#
################################################################################

@doc Markdown.doc"""
    regular_matrix_algebra(A::Union{ AlgAss, AlgGrp }) -> AlgMat, AbsAlgAssMor

> Returns the matrix algebra $B$ generated by the right representation matrices
> of the basis elements of $A$ and a map from $B$ to $A$.
"""
function regular_matrix_algebra(A::Union{ AlgAss, AlgGrp })
  K = base_ring(A)
  B = matrix_algebra(K, [ representation_matrix(A[i], :right) for i = 1:dim(A) ], isbasis = true)
  return B, hom(B, A, identity_matrix(K, dim(A)), identity_matrix(K, dim(A)))
end

###############################################################################
#
#  Construction of a crossed product algebra
#
###############################################################################

function find_elem(G::Array{T,1}, el::T) where T
  i=1
  while true
    if el.prim_img==G[i].prim_img
      return i
    end
    i+=1
  end
end


#K/Q is a Galois extension.
function CrossedProductAlgebra(K::AnticNumberField, G::Array{T,1}, cocval::Array{nf_elem, 2}) where T

  n=degree(K)
  m=length(G)
  #=
  Multiplication table
  I order the basis in this way:
  First, I put the basis of the Galois Group, then the product of them with the first
  element of basis of the order and so on...
  =#
  
  M=Array{fmpq,3}(undef, n*m, n*m, n*m)
  for i=1:n*m
    for j=1:n*m
      for s=1:n*m
        M[i,j,s]=fmpq(0)
      end
    end
  end
  B=basis(K)
  for i=1:n
    for j=1:m
      #I have the element B[i]*G[j]
      for k=1:n
        for h=1:m
          # I take the element B[k]*G[h]
          # and I take the product 
          # B[i]*G[j]* B[k]*G[h]=B[i]*G[j](B[k])*c[j,h]*(G[j]*G[h])
          ind=find_elem(G,G[h] * G[j]) 
          x=B[i]*G[j](B[k])*cocval[j,h]
          #@show i, j, k,h,  ind,B[i],G[j](B[k]),cocval[j,h],  x
          for s=0:n-1
            M[j+(i-1)*n, h+(k-1)*n, ind+s*n]=coeff(x,s)
          end
          #@show M
        end
      end
    end
  end
  return AlgAss(FlintQQ, M)

end

function CrossedProductAlgebra(O::NfOrd, G::Array{T,1}, cocval::Array{nf_elem, 2}) where T

  n=degree(O)
  m=length(G)
  K=nf(O)
  #=
  Multiplication table
  I order the basis in this way:
  First, I put the basis of the Galois Group, then the product of them with the first
  element of basis of the order and so on...
  =#
  
  M=Array{fmpq,3}(undef, n*m, n*m, n*m)
  for i=1:n*m
    for j=1:n*m
      for s=1:n*m
        M[i,j,s]=fmpq(0)
      end
    end
  end
  B = basis(O, copy = false)
  el = O(0)
  for j=1:m
    for k=1:n
      l =O(G[j](K(B[k])), false)
      for h=1:m
        ind = find_elem(G, G[h] * G[j]) 
        t = O(cocval[j,h], false)
        for i=1:n
          #I have the element B[i]*G[j]
          # I take the element B[k]*G[h]
          # and I take the product 
          # B[i]*G[j]* B[k]*G[h]=B[i]*G[j](B[k])*c[j,h]*(G[j]*G[h])
          mul!(el, B[i], l)
          mul!(el, el, t)
          y = coordinates(el)
          for s=0:n-1
            M[j+(i-1)*m, h+(k-1)*m, ind+s*m] = y[s+1]
          end
        end
      end
    end
  end
  j1 = find_identity(G, *)
  j = find_elem(G, j1)
  O1 = fmpq[0 for i=1:n*m]
  O1[j] = fmpq(1)
  A = AlgAss(FlintQQ, M, O1)
  A.issimple = 1
  return A

end

################################################################################
#
#  Quaternion algebras
#
################################################################################

function quaternion_algebra(a::Int, b::Int)
  
  M = Array{fmpq,3}(undef, 4,4,4)
  for i = 1:4
    for j = 1:4
      for k = 1:4
        M[i,j,k] = 0
      end
    end
  end  
  M[1,1,1] = 1 # 1*1=1
  M[1,2,2] = 1 # 1*i=i
  M[1,3,3] = 1 # 1*j=j
  M[1,4,4] = 1 # 1*ij=1
  
  M[2,1,2] = 1
  M[2,2,1] = a
  M[2,3,4] = 1
  M[2,4,3] = a
  
  M[3,1,3] = 1
  M[3,2,4] = -1
  M[3,3,1] = b
  M[3,4,2] = -b
  
  M[4,1,4] = 1
  M[4,2,3] = -a
  M[4,3,2] = b
  M[4,4,1] = -a*b
  O = fmpq[1, 0, 0, 0]
  return AlgAss(FlintQQ, M, O)
  
end
