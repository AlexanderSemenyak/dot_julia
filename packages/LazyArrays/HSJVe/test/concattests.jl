using LazyArrays, LinearAlgebra, Test
import LazyArrays: MemoryLayout, HcatLayout, VcatLayout, DenseColumnMajor, materialize!, MulAdd

@testset "concat" begin
    @testset "Vcat" begin
        A = Vcat(Vector(1:10), Vector(1:20))
        @test @inferred(length(A)) == 30
        @test @inferred(A[5]) == A[15] == 5
        @test_throws BoundsError A[31]
        @test reverse(A) == Vcat(Vector(reverse(1:20)), Vector(reverse(1:10)))
        b = Array{Int}(undef, 31)
        @test_throws DimensionMismatch copyto!(b, A)
        b = Array{Int}(undef, 30)
        @test @allocated(copyto!(b, A)) == 0
        @test b == vcat(A.arrays...)
        @test copy(A) isa Vcat
        @test copy(A) == A
        @test copy(A) !== A
        @test vec(A) === A
        @test A' == transpose(A) == Vector(A)'

        A = Vcat(1:10, 1:20)
        @test @inferred(length(A)) == 30
        @test @inferred(A[5]) == A[15] == 5
        @test_throws BoundsError A[31]
        @test reverse(A) == Vcat(reverse(1:20), reverse(1:10))
        b = Array{Int}(undef, 31)
        @test_throws DimensionMismatch copyto!(b, A)
        b = Array{Int}(undef, 30)
        @test @allocated(copyto!(b, A)) == 0
        @test b == vcat(A.arrays...)
        @test copy(A) === A
        @test vec(A) === A
        @test A' == transpose(A) == Vector(A)'
        @test A' === Hcat((1:10)', (1:20)')
        @test transpose(A) === Hcat(transpose(1:10), transpose(1:20))

        A = Vcat(randn(2,10), randn(4,10))
        @test @inferred(length(A)) == 60
        @test @inferred(size(A)) == (6,10)
        @test_throws BoundsError A[61]
        @test_throws BoundsError A[7,1]
        b = Array{Float64}(undef, 7,10)
        @test_throws DimensionMismatch copyto!(b, A)
        b = Array{Float64}(undef, 6,10)
        @test @allocated(copyto!(b, A)) == 0
        @test b == vcat(A.arrays...)
        @test copy(A) isa Vcat
        @test copy(A) == A
        @test copy(A) !== A
        @test vec(A) == vec(Matrix(A))
        @test A' == transpose(A) == Matrix(A)'

        A = Vcat(randn(2,10).+im.*randn(2,10), randn(4,10).+im.*randn(4,10))
        @test eltype(A) == ComplexF64
        @test @inferred(length(A)) == 60
        @test @inferred(size(A)) == (6,10)
        @test_throws BoundsError A[61]
        @test_throws BoundsError A[7,1]
        b = Array{ComplexF64}(undef, 7,10)
        @test_throws DimensionMismatch copyto!(b, A)
        b = Array{ComplexF64}(undef, 6,10)
        @test @allocated(copyto!(b, A)) == 0
        @test b == vcat(A.arrays...)
        @test copy(A) isa Vcat
        @test copy(A) == A
        @test copy(A) !== A
        @test vec(A) == vec(Matrix(A))
        @test A' == Matrix(A)'
        @test transpose(A) == transpose(Matrix(A))

        @test Vcat() isa Vcat{Any,1,Tuple{}}

        A = Vcat(1,zeros(3,1))
        @test_broken A isa AbstractMatrix
    end
    @testset "Hcat" begin
        A = Hcat(1:10, 2:11)
        @test_throws BoundsError A[1,3]
        @test @inferred(size(A)) == (10,2)
        @test @inferred(A[5]) == @inferred(A[5,1]) == 5
        @test @inferred(A[11]) == @inferred(A[1,2]) == 2
        b = Array{Int}(undef, 11, 2)
        @test_throws DimensionMismatch copyto!(b, A)
        b = Array{Int}(undef, 10, 2)
        @test @allocated(copyto!(b, A)) == 0
        @test b == hcat(A.arrays...)
        @test copy(A) === A
        @test vec(A) == vec(Matrix(A))
        @test vec(A) === Vcat(1:10,2:11)
        @test A' == Matrix(A)'
        @test A' === Vcat((1:10)', (2:11)')

        A = Hcat(Vector(1:10), Vector(2:11))
        b = Array{Int}(undef, 10, 2)
        copyto!(b, A)
        @test b == hcat(A.arrays...)
        @test @allocated(copyto!(b, A)) == 0
        @test copy(A) isa Hcat
        @test copy(A) == A
        @test copy(A) !== A
        @test vec(A) == vec(Matrix(A))
        @test vec(A) === Vcat(A.arrays...)
        @test A' == Matrix(A)'

        A = Hcat(1, zeros(1,5))
        @test A == hcat(1, zeros(1,5))
        @test vec(A) == vec(Matrix(A))
        @test_broken A' == Matrix(A)'

        A = Hcat(Vector(1:10), randn(10, 2))
        b = Array{Float64}(undef, 10, 3)
        copyto!(b, A)
        @test b == hcat(A.arrays...)
        @test @allocated(copyto!(b, A)) == 0
        @test vec(A) == vec(Matrix(A))

        A = Hcat(randn(5).+im.*randn(5), randn(5,2).+im.*randn(5,2))
        b = Array{ComplexF64}(undef, 5, 3)
        copyto!(b, A)
        @test b == hcat(A.arrays...)
        @test @allocated(copyto!(b, A)) == 0
        @test vec(A) == vec(Matrix(A))
        @test A' == Matrix(A)'
        @test transpose(A) == transpose(Matrix(A))
    end


    @testset "Special pads" begin
        A = Vcat([1,2,3], Zeros(7))
        B = Vcat([1,2], Zeros(8))

        C = @inferred(A+B)
        @test C isa Vcat{Float64,1}
        @test C.arrays[1] isa Vector{Float64}
        @test C.arrays[2] isa Zeros{Float64}
        @test C == Vector(A) + Vector(B)


        B = Vcat([1,2], Ones(8))

        C = @inferred(A+B)
        @test C isa Vcat{Float64,1}
        @test C.arrays[1] isa Vector{Float64}
        @test C.arrays[2] isa Ones{Float64}
        @test C == Vector(A) + Vector(B)

        B = Vcat([1,2], randn(8))

        C = @inferred(A+B)
        @test C isa BroadcastArray{Float64}
        @test C == Vector(A) + Vector(B)

        B = Vcat(SVector(1,2), Ones(8))
        C = @inferred(A+B)
        @test C isa Vcat{Float64,1}
        @test C.arrays[1] isa Vector{Float64}
        @test C.arrays[2] isa Ones{Float64}
        @test C == Vector(A) + Vector(B)


        A = Vcat(SVector(3,4), Zeros(8))
        B = Vcat(SVector(1,2), Ones(8))
        C = @inferred(A+B)
        @test C isa Vcat{Float64,1}
        @test C.arrays[1] isa SVector{2,Int}
        @test C.arrays[2] isa Ones{Float64}
        @test C == Vector(A) + Vector(B)
    end

    @testset "Empty Vcat" begin
        @test @inferred(Vcat{Int}([1])) == [1]        
        @test @inferred(Vcat{Int}(())) == @inferred(Vcat{Int}()) == Int[]        
    end

    @testset "in" begin
        @test 1 in Vcat(1, 1:10_000_000_000)
        @test 100_000_000 in Vcat(1, 1:10_000_000_000)
    end

    @testset "convert" begin
        for T in (Float32, Float64, ComplexF32, ComplexF64)
            Z = Vcat(zero(T),Zeros{T}(10))
            @test convert(AbstractArray,Z) ≡ AbstractArray(Z) ≡ Z
            @test convert(AbstractArray{T},Z) ≡ AbstractArray{T}(Z) ≡ Z
            @test convert(AbstractVector{T},Z) ≡ AbstractVector{T}(Z) ≡ Z
        end
    end

    @testset "setindex!" begin
        x = randn(5)
        y = randn(6)
        A = Vcat(x, y, 3)
        A[1] = 1
        @test A[1] == x[1] == 1
        A[6] = 2
        @test A[6] == y[1] == 2
        @test_throws MethodError A[12] = 3
        @test_throws BoundsError A[13] = 3

        x = randn(2,2); y = randn(3,2)
        A = Vcat(x,y)
        A[1,1] = 1
        @test A[1,1] == x[1,1] == 1
        A[3,1] = 2
        @test A[3,1] == y[1,1] == 2
        A[6] = 3
        @test A[1,2] == x[1,2] == 3

        x = randn(2,2); y = randn(2,3)
        B = Hcat(x,y)
        B[1,1] = 1
        @test B[1,1] == x[1,1] == 1
        B[1,3] = 2
        @test B[1,3] == y[1,1] == 2
    end

    @testset "fill!" begin
        A = Vcat([1,2,3],[4,5,6])
        fill!(A,2)
        @test A == fill(2,6)

        A = Vcat(2,[4,5,6])
        @test fill!(A,2) == fill(2,4)
        @test_throws ArgumentError fill!(A,3)

        A = Hcat([1,2,3],[4,5,6])
        fill!(A,2)
        @test A == fill(2,3,2)
    end

    @testset "Any/All" begin
        @test all(Vcat(true, Fill(true,100_000_000)))
        @test any(Vcat(false, Fill(true,100_000_000)))
        @test all(iseven, Vcat(2, Fill(4,100_000_000)))
        @test any(iseven, Vcat(2, Fill(1,100_000_000)))
        @test_throws TypeError all(Vcat(1))
        @test_throws TypeError any(Vcat(1))
    end

    @testset "isbitsunion #45" begin 
        @test copyto!(Vector{Vector{Int}}(undef,6), Vcat([[1], [2], [3]], [[1], [2], [3]])) ==
            [[1], [2], [3], [1], [2], [3]]

        a = Vcat{Union{Float64,UInt8}}([1.0], [UInt8(1)])
        @test Base.isbitsunion(eltype(a))
        r = Vector{Union{Float64,UInt8}}(undef,2)
        @test copyto!(r, a) == a
        @test r == a
        @test copyto!(Vector{Float64}(undef,2), a) == [1.0,1.0]
    end

    @testset "Mul" begin
        A = Hcat([1.0 2.0],[3.0 4.0])
        B = Vcat([1.0,2.0],[3.0,4.0])
    
        @test MemoryLayout(typeof(A)) isa HcatLayout{Tuple{DenseColumnMajor,DenseColumnMajor}}
        @test MemoryLayout(typeof(B)) isa VcatLayout{Tuple{DenseColumnMajor,DenseColumnMajor}}
        @test A*B == Matrix(A)*Vector(B) == mul!(Vector{Float64}(undef,1),A,B) == (Vector{Float64}(undef,1) .= @~ A*B)
        @test materialize!(MulAdd(1.1,A,B,2.2,[5.0])) == 1.1*Matrix(A)*Vector(B)+2.2*[5.0]

        A = Hcat([1.0 2.0; 3 4],[3.0 4.0; 5 6])
        B = Vcat([1.0,2.0],[3.0,4.0])
        @test MemoryLayout(typeof(A)) isa HcatLayout{Tuple{DenseColumnMajor,DenseColumnMajor}}
        @test MemoryLayout(typeof(B)) isa VcatLayout{Tuple{DenseColumnMajor,DenseColumnMajor}}
        @test A*B == Matrix(A)*Vector(B) == mul!(Vector{Float64}(undef,2),A,B) == (Vector{Float64}(undef,2) .= @~ A*B)
        @test materialize!(MulAdd(1.1,A,B,2.2,[5.0,6])) ≈ 1.1*Matrix(A)*Vector(B)+2.2*[5.0,6]

        A = Hcat([1.0 2.0; 3 4],[3.0 4.0; 5 6])
        B = Vcat([1.0 2.0; 3 4],[3.0 4.0; 5 6])
        @test MemoryLayout(typeof(A)) isa HcatLayout{Tuple{DenseColumnMajor,DenseColumnMajor}}
        @test MemoryLayout(typeof(B)) isa VcatLayout{Tuple{DenseColumnMajor,DenseColumnMajor}}
        @test A*B == Matrix(A)*Matrix(B) == mul!(Matrix{Float64}(undef,2,2),A,B) == (Matrix{Float64}(undef,2,2) .= @~ A*B)
        @test materialize!(MulAdd(1.1,A,B,2.2,[5.0 6; 7 8])) ≈ 1.1*Matrix(A)*Matrix(B)+2.2*[5.0 6; 7 8]
    end
end