using SumProductNetworks, Distributions
using Test

@testset "Topological Order Test" begin
    C = 10
    Ch = 4
    D = 10

    layer1 = MultivariateFeatureLayer(collect(1:C), rand(C, D), rand(Bool, C, D), nothing)
    layer2 = MultivariateFeatureLayer(collect(1:C), rand(C, D), rand(Bool, C, D), nothing)
    layer3 = ProductLayer(collect(1:C), rand(Int, Ch, C), SPNLayer[], nothing)

    layer4 = MultivariateFeatureLayer(collect(1:C), rand(C, D), rand(Bool, C, D), nothing)
    layer5 = MultivariateFeatureLayer(collect(1:C), rand(C, D), rand(Bool, C, D), nothing)
    layer6 = ProductLayer(collect(1:C), rand(Int, Ch, C), SPNLayer[], nothing)

    spn = SumLayer(collect(1:C), rand(Int, Ch, C), rand(Ch, C), SPNLayer[], nothing)

    # connect layers
    push!(spn.children, layer3)
    push!(spn.children, layer6)

    layer3.parent = spn
    layer6.parent = spn

    push!(layer3.children, layer1)
    push!(layer3.children, layer2)
    push!(layer6.children, layer4)
    push!(layer6.children, layer5)

    layer1.parent = layer3
    layer2.parent = layer3
    layer4.parent = layer6
    layer5.parent = layer6

    # actual test
    computationOrder = getOrderedLayers(spn)

    # expected computation order
    # 1, 2, 3, 4, 5, 6, spn

    @test computationOrder[end] == spn
    @test computationOrder[1] == layer1
    @test computationOrder[2] == layer2
    @test computationOrder[3] == layer3
    @test computationOrder[4] == layer4
    @test computationOrder[5] == layer5
    @test computationOrder[6] == layer6
end

@testset "Structure Generation" begin

    # create dummy data
    X = randn(150, 4)
    Y = rand(1:3, 150)

    (N, D) = size(X)
    C = length(unique(Y)) # number of classes

    @testset "Bayesian Layer Structure" begin

        M = 4 # number of children under a sum node
        K = 4 # number of children under a product node
        L = 2 # number of product-sum layers (excluding the root)
        S = 2 # states

        spn = create_bayesian_discrete_layered_spn(M, K, L, N, D, S; α = 1.0, β = 1.0, γ = 1.0)

        computationOrder = getOrderedLayers(spn)
        @test length(computationOrder) == (2 * L) + 2 + 1 # 2 * L + root + full fact prod + categorical dists


    end

    @testset "Filter Structure" begin

        P = 10
        M = 2
        W = 0
        G = 2
        K = 1

        spn = SumLayer([1], Array{Int,2}(undef, 0, 0), Array{Float32, 2}(undef, 0, 0), SPNLayer[], nothing)
        imageStructure!(spn, C, D, G, K; parts = P, mixtures = M, window = W)

        computationOrder = getOrderedLayers(spn)
        @test length(computationOrder) == 5

        @test size(computationOrder[1]) == (4*M*P*C, 1)
        @test size(computationOrder[2]) == (M*P*C, 4)
        @test size(computationOrder[3]) == (P*C, M)
        @test size(computationOrder[4]) == (C, P)
        @test size(computationOrder[5]) == (1, C)
    end
end
