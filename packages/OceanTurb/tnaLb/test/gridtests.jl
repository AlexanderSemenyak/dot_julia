# --
# Define tests
# --

function test_uniform_grid_type(T, N, L)
  grid = UniformGrid(T, N, L)
  T == typeof(grid.L) && T == eltype(grid.zc) && T == eltype(grid.zf)
end

function test_uniform_grid_spacing(T, N, L)
  Δ = T(L/N)
  grid = UniformGrid(T, N, L)
  Δ == grid.Δc && Δ == grid.Δf
end

function test_uniform_grid_limits_zc_left(T, N, L)
  Δ = L/N
  grid = UniformGrid(T, N, L)
  grid.zc[1] ≈ -L+0.5Δ
end

function test_uniform_grid_limits_zc_right(T, N, L)
  Δ = L/N
  grid = UniformGrid(T, N, L)
  grid.zc[N] ≈ -0.5Δ
end

function test_uniform_grid_limits_zf_left(T, N, L)
  Δ = L/N
  grid = UniformGrid(T, N, L)
  grid.zf[1] ≈ -L
end

function test_uniform_grid_limits_zf_right(T, N, L)
  Δ = L/N
  grid = UniformGrid(T, N, L)
  grid.zf[N+1] ≈ 0
end
