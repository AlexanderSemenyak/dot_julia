using Stheno: GPC, ZeroMean, ConstMean, CustomMean, ZeroKernel
using Stheno: EQ, Exp

@testset "gp" begin

    # Ensure that basic functionality works as expected.
    @testset "GP" begin
        rng, gpc, N, N′ = MersenneTwister(123456), GPC(), 5, 6
        m, k = CustomMean(sin), EQ()
        f = GP(m, k, gpc)
        x = collect(range(-1.0, 1.0; length=N))
        x′ = collect(range(-1.0, 1.0; length=N′))

        @test mean_vector(f, x) == ew(m, x)
        @test cov(f, x) == pw(k, x)
        @test cov_diag(f, x) == diag(cov(f, x))
        @test cov(f, x, x) == pw(k, x, x)
        @test cov(f, x, x′) == pw(k, x, x′)
        @test cov(f, x, x′) ≈ cov(f, x′, x)'
    end

    # Check that mean-function specialisations work as expected.
    @testset "sugar" begin
        m = 5.1
        @test GP(5, EQ(), GPC()).m isa ConstMean
        @test GP(EQ(), GPC()).m isa ZeroMean
    end

    # Test the creation of indepenent GPs.
    @testset "independent GPs" begin
        rng, N, N′ = MersenneTwister(123456), 5, 6
        x, x′ = randn(rng, N), randn(rng, N′)

        # Specification of two independent GPs
        gpc = GPC()
        m1, m2 = ZeroMean(), ConstMean(5)
        k1, k2 = EQ(), EQ()
        f1, f2 = GP(m1, k1, gpc), GP(m2, k2, gpc)

        @test mean_vector(f1, x) == ew(m1, x)
        @test mean_vector(f2, x) == ew(m2, x)

        @test cov(f1, f2, x, x′) == zeros(N, N′)
        @test cov_diag(f1, x) == ones(N)

        @test cov(f1, f1, x′, x) ≈ cov(f1, f1, x, x′)'
    end
end
