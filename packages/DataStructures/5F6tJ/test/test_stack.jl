@testset "Stacks" begin

    @testset "Constructors" begin
        s = Stack{Int}()
        @test isa(s, Stack{Int})

        s = Stack{Int}(5)
        @test isa(s, Stack{Int})
    end

    @testset "Core Functionality" begin
        s = Stack{Int}(5)
        n = 100

        @test isa(s, Stack{Int})
        @test length(s) == 0
        @test isempty(s)
        @test_throws ArgumentError top(s)
        @test_throws ArgumentError pop!(s)

        for i = 1 : n
            push!(s, i)
            @test top(s) == i
            @test !isempty(s)
            @test length(s) == i
        end

        for i = 1 : n
            x = pop!(s)
            @test x == n - i + 1
            if i < n
                @test top(s) == n - i
            else
                @test_throws ArgumentError top(s)
            end
            @test isempty(s) == (i == n)
            @test length(s) == n - i
        end
    end

    @testset "empty!" begin
        s = Stack{Int}(1)
        push!(s, 10)
        @test length(empty!(s)) == 0
    end

    @testset "iter should return a LIFO collection" begin
        stk = Stack{Int}(10)
        #an array to check iteration sequence against
        arr = Int64[]

        n = 100

        for i = 1:n
            push!(stk, i)
            push!(arr, i)
        end

        @testset "iterator" begin
            index = length(arr)
            for i in stk
                @test(arr[index] == i)
                index -= 1
            end
        end

        @testset "reverse iterator" begin
            index = 1
            for i in reverse_iter(stk)
                @test(arr[index] == i)
                index += 1
            end
        end

        @test arr == [i for i in reverse_iter(stk)]
        @test reverse(arr) == [i for i in stk]
    end

end # @testset Stack
