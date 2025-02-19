# Unit test for the lin-solve mehtods (in src/LinSolver.jl)
# The "Gun" problem form gun_native.jl

using NonlinearEigenproblemsTest
using NonlinearEigenproblems
using Test
using LinearAlgebra

@testset "linsolvers" begin
    TOL = 1e-10;
    nep = nep_gallery("nlevp_native_gun")

    n = size(nep,1);
    λ = 250^2+1im;

    x=ones(n);

    M = compute_Mder(nep, λ)

    @bench @testset "basic functionality" begin
        linsolver1=backslash_linsolvercreator(nep,λ);
        y1=lin_solve(linsolver1,x)

        linsolver2=default_linsolvercreator(nep,λ);
        y2=lin_solve(linsolver1,x)

        @test y1 ≈ y2

        y3=M\x;
        @test y1 ≈ y3
        @test y2 ≈ y3
        F=factorize(M);
        y4=F\x;
        @test y1 ≈ y4
        @test y2 ≈ y4
        @test y3 ≈ y4

        normy1=norm(y1);
        normy2=norm(y2);
        normy3=norm(y3);
        normy4=norm(y4);

        @info "norm(y1,1)=$normy1"
        # To display further digits
        @info "normy1-round(128*normy1)/128=$(normy1-round(128*normy1)/128) (for further digits)"
        @info "norm(y2,1)=$(norm(y2))"
        @info "normy2-round(128*normy2)/128=$(normy2-round(128*normy2)/128)"
        @info "norm(y3,1)=$(norm(y3))"
        @info "normy3-round(128*normy3)/128=$(normy3-round(128*normy3)/128)"
        @info "norm(y4,1)=$(norm(y4))"
        @info "normy4-round(128*normy4)/128=$(normy4-round(128*normy4)/128)"

        M1norm=norm(M,1);
        r1=M*y1-x;
        r2=M*y2-x;
        r3=M*y3-x;
        r4=M*y4-x;
        @test norm(r1)/M1norm < eps()


        # By first multiplying with M
        z=M*x;
        normz=norm(z)
        @info "z=M*x; norm(z)=$normz x'*z=$(x'*z)"
        @info "normz-floor(normz*10)/10=$(normz-Int(floor(normz*10))/10)"
        t=M\z;
        @info "norm(M\\z-x)=$(norm(t-x))"
        @test norm(t-x)/M1norm < eps()
    end

    @bench @testset "umfpack iterative refinements" begin
        # Test using max 0 vs max 2 iterative refinements. There is little point in testing
        # max 1 refinement, since in practice only a single refinement is used anyway.
        c0 = default_linsolvercreator(nep, λ; umfpack_refinements = 0)
        c2 = default_linsolvercreator(nep, λ)

        # do a warmup-solve to force JIT compilation to get accurate memory measurements
        lin_solve(c0, x)

        r0 = @timed lin_solve(c0, x)
        r2 = @timed lin_solve(c2, x)

        # test that the norm is at least 10 times bigger with no iterative refinements
        norm0 = norm(M*r0[1] - x)
        norm2 = norm(M*r2[1] - x)
        @test norm0 > 10 * norm2

        # test that much less memory is allocated with no iterative refinements
        memory0 = r0[3]
        memory2 = r2[3]
        @test memory0 < memory2 * 0.75
    end



    @testset "eigsolvers" begin

        @bench @testset "DefaultEigSolver - full" begin
            Random.seed!(0)
            n = 20
            A = rand(ComplexF64, n, n)
            B = rand(ComplexF64, n, n)

            eigsolver1 = DefaultEigSolver(A,B)
            eigsolver2 = DefaultEigSolver(B\A)

            λ1,v1 = eig_solve(eigsolver1, nev=3)
            λ2,v2 = eig_solve(eigsolver2, nev=3)

            for i = 1:3
                @test λ1[i] ≈ λ2[i]
            end
        end

        @bench @testset "DefaultEigSolver - sparse" begin
            Random.seed!(0)
            n = 20
            A = sprand(ComplexF64, n, n, 0.25) + I
            B = sprand(ComplexF64, n, n, 0.25) + I

            eigsolver1 = DefaultEigSolver(A,B)
            eigsolver2 = DefaultEigSolver(sparse(Matrix(B)\Matrix(A)))

            λ1,v1 = eig_solve(eigsolver1, nev=3)
            λ2,v2 = eig_solve(eigsolver2, nev=3)

            for i = 1:3
                @test λ1[i] ≈ λ2[i]
            end
        end

        @bench @testset "NativeEigSolver" begin
            Random.seed!(0)
            n = 20
            A = rand(ComplexF64, n, n)
            B = rand(ComplexF64, n, n)

            eigsolver1 = NativeEigSolver(A,B)
            eigsolver2 = NativeEigSolver(B\A)

            λ1,v1 = eig_solve(eigsolver1, nev=3)
            λ2,v2 = eig_solve(eigsolver2, nev=3)

            for i = 1:3
                @test λ1[i] ≈ λ2[i]
            end
        end

        @bench @testset "NativeEigSSolver" begin
            Random.seed!(0)
            n = 20
            A = sprand(ComplexF64, n, n, 0.25) + I
            B = sprand(ComplexF64, n, n, 0.25) + I

            eigsolver1 = NativeEigSSolver(A,B)
            eigsolver2 = NativeEigSSolver(sparse(Matrix(B)\Matrix(A)))

            λ1,v1 = eig_solve(eigsolver1, nev=3)
            λ2,v2 = eig_solve(eigsolver2, nev=3)

            for i = 1:3
                @test λ1[i] ≈ λ2[i]
            end
        end

    end
end
