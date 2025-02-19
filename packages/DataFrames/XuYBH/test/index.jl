module TestIndex

using Test, DataFrames
using DataFrames: Index, SubIndex, fuzzymatch

i = Index()
push!(i, :A)
push!(i, :B)

inds = Any[1,
           big(1),
           :A,
           [true, false],
           [1],
           [big(1)],
           big(1):big(1),
           [:A],
           Union{Int, Missing}[1],
           Union{BigInt, Missing}[big(1)],
           Union{Symbol, Missing}[:A],
           Any[1],
           Any[:A]]

for ind in inds
    if ind == :A || ndims(ind) == 0
        @test i[ind] == 1
    else
        @test (i[ind] == [1])
    end
end

@test_throws MethodError i[1.0]
@test_throws ArgumentError i[true]
@test_throws ArgumentError i[false]
@test_throws ArgumentError i[Union{Bool, Missing}[true, false]]
@test_throws ArgumentError i[Any[1, missing]]
@test_throws ArgumentError i[[1, missing]]
@test_throws ArgumentError i[[true, missing]]
@test_throws ArgumentError i[Any[true, missing]]
@test_throws MethodError i[[:A, missing]]
@test_throws MethodError i[Any[:A, missing]]
@test_throws ArgumentError i[1.0:1.0]
@test_throws ArgumentError i[[1.0]]
@test_throws ArgumentError i[Any[1.0]]
@test_throws BoundsError i[0]
@test_throws BoundsError i[10]
@test_throws ArgumentError i[:x]
@test_throws BoundsError i[1:3]
@test_throws ArgumentError i[[1,1]]
@test_throws ArgumentError i[[:A,:A]]
@test_throws BoundsError i[Not(0)]
@test_throws BoundsError i[Not(10)]
@test_throws ArgumentError i[Not(:x)]
@test_throws BoundsError i[Not(1:3)]
@test_throws ArgumentError i[Not([1,1])]
@test_throws ArgumentError i[Not([:A,:A])]

@test i[1:1] == 1:1

@test_throws BoundsError i[[true]]
@test_throws BoundsError i[true:true]
@test_throws BoundsError i[[true, false, true]]

@test_throws ArgumentError i[["a"]]
@test_throws ArgumentError i[Any["a"]]

@test i[[]] == Int[]
@test i[Int[]] == Int[]
@test i[Symbol[]] == Int[]
@test i[:] == 1:length(i)
@test i[Not(Not(:))] == 1:length(i)
@test i[Not(1:0)] == 1:length(i)

@test names(i) == [:A,:B]
@test names!(i, [:a,:a], makeunique=true) == Index([:a,:a_1])
@test_throws ArgumentError names!(i, [:a,:a])
@test names!(i, [:a,:b]) == Index([:a,:b])
@test rename(i, Dict(:a=>:A, :b=>:B)) == Index([:A,:B])
@test rename(i, :a => :A) == Index([:A,:b])
@test rename(i, :a => :a) == Index([:a,:b])
@test rename(i, [:a => :A]) == Index([:A,:b])
@test rename(i, [:a => :a]) == Index([:a,:b])
@test rename(x->Symbol(uppercase(string(x))), i) == Index([:A,:B])
@test rename(x->Symbol(lowercase(string(x))), i) == Index([:a,:b])

@test delete!(i, :a) == Index([:b])
push!(i, :C)
@test delete!(i, 1) == Index([:C])

i = Index([:A, :B, :C, :D, :E])
i2 = copy(i)
names!(i2, reverse(names(i2)))
names!(i2, reverse(names(i2)))
@test names(i2) == names(i)
for name in names(i)
  i2[name] # Issue #715
end

i = Index([:A, :B, :C, :D, :E])
si1 = SubIndex(i, :)
si2 = SubIndex(i, 3:5)
si3 = SubIndex(i, [3,4,5])
si4 = SubIndex(i, [false, false, true, true, true])
si5 = SubIndex(i, [:C, :D, :E])
si6 = SubIndex(i, Not(Not([:C, :D, :E])))
si7 = SubIndex(i, Not(1:2))

@test copy(si1) == i
@test copy(si2) == Index([:C, :D, :E])
@test copy(si3) == Index([:C, :D, :E])
@test copy(si4) == Index([:C, :D, :E])
@test copy(si5) == Index([:C, :D, :E])
@test copy(si6) == Index([:C, :D, :E])
@test copy(si7) == Index([:C, :D, :E])

@test_throws ArgumentError SubIndex(i, 1)
@test_throws ArgumentError SubIndex(i, :A)
@test_throws ArgumentError SubIndex(i, true)
@test si1 isa Index
@test si2.cols == 3:5
@test si2.remap == -1:3
@test si3.cols == 3:5
@test si3.remap == Int[]
@test !haskey(si3, :A)
@test si3.remap == [0, 0, 1, 2, 3]
@test si4.cols == 3:5
@test si4.remap == Int[]
@test !haskey(si4, :A)
@test si4.remap == [0, 0, 1, 2, 3]
@test si5.cols == 3:5
@test si5.remap == Int[]
@test !haskey(si5, :A)
@test si5.remap == [0, 0, 1, 2, 3]
@test si6.cols == 3:5
@test si6.remap == Int[]
@test !haskey(si6, :A)
@test si6.remap == [0, 0, 1, 2, 3]
@test si7.cols == 3:5
@test si7.remap == Int[]
@test !haskey(si7, :A)
@test si7.remap == [0, 0, 1, 2, 3]

@test length(si1) == 5
@test length(si2) == 3
@test length(si3) == 3
@test length(si4) == 3
@test length(si5) == 3
@test length(si6) == 3
@test length(si7) == 3

@test names(si1) == keys(si1) == [:A, :B, :C, :D, :E]
@test names(si2) == keys(si2) == [:C, :D, :E]
@test names(si3) == keys(si3) == [:C, :D, :E]
@test names(si4) == keys(si4) == [:C, :D, :E]
@test names(si5) == keys(si5) == [:C, :D, :E]
@test names(si6) == keys(si5) == [:C, :D, :E]
@test names(si7) == keys(si5) == [:C, :D, :E]

@test_throws ArgumentError haskey(si3, true)
@test haskey(si3, 1)
@test !haskey(si3, 0)
@test !haskey(si3, 4)
@test haskey(si3, :D)
@test !haskey(si3, :A)
@test si3[:C] == 1
@test si3[names(i)] == [0, 0, 1, 2, 3]

@testset "selector mutation" begin
    df = DataFrame(a=1:5, b=11:15, c=21:25)
    selector1 = [3,2]
    dfv1 = view(df, :, selector1)
    dfr1 = view(df, 2, selector1)
    selector2 = [1]
    dfv2 = view(dfv1, :, selector2)
    dfr2 = view(dfr1, selector2)
    @test names(dfv1) == [:c, :b]
    @test names(dfv2) == [:c]
    @test names(dfr1) == [:c, :b]
    @test names(dfr2) == [:c]
    selector1[1] = 1
    @test names(dfv1) == [:a, :b]
    @test names(dfv2) == [:c]
    @test names(dfr1) == [:a, :b]
    @test names(dfr2) == [:c]
    selector3 = [:c, :b]
    dfv3 = view(df, :, selector3)
    dfr3 = view(df, 2, selector3)
    @test names(dfv3) == [:c, :b]
    @test names(dfr3) == [:c, :b]
    selector3[1] = :a
    @test names(dfv3) == [:c, :b]
    @test names(dfr3) == [:c, :b]
end

@testset "fuzzy matching and ArgumentError" begin
    i = Index()
    push!(i, :x1)
    push!(i, :x12)
    push!(i, :x131)
    push!(i, :y13)
    push!(i, :yy13)
    @test_throws ArgumentError i[:x13]
    @test_throws ArgumentError i[:xx13]
    @test_throws ArgumentError i[:yy14]
    @test_throws ArgumentError i[:abcd]
    @test fuzzymatch(i.lookup, :x13) == [:x1, :x12, :x131, :y13, :yy13]
    @test fuzzymatch(i.lookup, :xx1314) == [:x131]
    @test fuzzymatch(i.lookup, :yy14) == [:yy13, :y13]
    @test isempty(fuzzymatch(i.lookup, :abcd))
end

@testset "Regex indexing" begin
    i = Index()
    push!(i, :x1)
    push!(i, :x12)
    push!(i, :x131)
    push!(i, :y13)
    push!(i, :yy13)
    @test i[r"x1."] == [2, 3]
    @test isempty(i[r"xx"])
    @test i[r""] == 1:5
    @test names(SubIndex(i, r"x1.")) == [:x12, :x131]
    @test isempty(names(SubIndex(i, r"xx")))
    @test names(SubIndex(i, r"")) == names(i)
    @test DataFrames._names(SubIndex(i, r"x1.")) == [:x12, :x131]
    @test isempty(DataFrames._names(SubIndex(i, r"xx")))
    @test DataFrames._names(SubIndex(i, r"")) == names(i)
    @test DataFrames.parentcols(SubIndex(i, r"x1.")) == [2, 3]
    @test isempty(DataFrames.parentcols(SubIndex(i, r"xx")))
    @test DataFrames.parentcols(SubIndex(i, r"")) == 1:5

    i2 = SubIndex(i, r"")
    @test i2[r"x1."] == [2, 3]
    @test isempty(i2[r"xx"])
    @test i2[r""] == 1:5
    @test names(SubIndex(i2, r"x1.")) == [:x12, :x131]
    @test isempty(names(SubIndex(i2, r"xx")))
    @test names(SubIndex(i2, r"")) == names(i)
    @test DataFrames._names(SubIndex(i2, r"x1.")) == [:x12, :x131]
    @test isempty(DataFrames._names(SubIndex(i2, r"xx")))
    @test DataFrames._names(SubIndex(i2, r"")) == names(i2)
    @test DataFrames.parentcols(SubIndex(i2, r"x1.")) == [2, 3]
    @test isempty(DataFrames.parentcols(SubIndex(i2, r"xx")))
    @test DataFrames.parentcols(SubIndex(i2, r"")) == 1:5

    i3 = SubIndex(i, r"x1.")
    @test i3[r"x1.$"] == [1]
    @test isempty(i3[r"xx"])
    @test i3[r""] == 1:2
    @test names(SubIndex(i3, r"x1.$")) == [:x12]
    @test isempty(names(SubIndex(i3, r"xx")))
    @test names(SubIndex(i3, r"")) == names(i3)
    @test DataFrames._names(SubIndex(i3, r"x1.$")) == [:x12]
    @test isempty(DataFrames._names(SubIndex(i3, r"xx")))
    @test DataFrames._names(SubIndex(i3, r"")) == names(i3)
    @test DataFrames.parentcols(SubIndex(i3, r"x1.$")) == [1]
    @test isempty(DataFrames.parentcols(SubIndex(i3, r"xx")))
    @test DataFrames.parentcols(SubIndex(i3, r"")) == 1:2
end

@testset "Not indexing" begin
    i = Index()
    push!(i, :x1)
    push!(i, :x12)
    push!(i, :x131)
    push!(i, :y13)
    push!(i, :yy13)
    @test i[Not(Not(r"x1."))] == [2, 3]
    @test isempty(i[Not(Not(r"xx"))])
    @test i[Not(Not(r""))] == 1:5
    @test names(SubIndex(i, Not(Not(r"x1.")))) == [:x12, :x131]
    @test isempty(names(SubIndex(i, Not(Not(r"xx")))))
    @test names(SubIndex(i, Not(Not(r"")))) == names(i)
    @test DataFrames._names(SubIndex(i, Not(Not(r"x1.")))) == [:x12, :x131]
    @test isempty(DataFrames._names(SubIndex(i, Not(Not(r"xx")))))
    @test DataFrames._names(SubIndex(i, Not(Not(r"")))) == names(i)
    @test DataFrames.parentcols(SubIndex(i, Not(Not(r"x1.")))) == [2, 3]
    @test isempty(DataFrames.parentcols(SubIndex(i, Not(Not(r"xx")))))
    @test DataFrames.parentcols(SubIndex(i, Not(Not(r"")))) == 1:5

    i2 = SubIndex(i, Not(Not(r"")))
    @test i2[Not(Not(r"x1."))] == [2, 3]
    @test isempty(i2[Not(Not(r"xx"))])
    @test i2[Not(Not(r""))] == 1:5
    @test names(SubIndex(i2, Not(Not(r"x1.")))) == [:x12, :x131]
    @test isempty(names(SubIndex(i2, Not(Not(r"xx")))))
    @test names(SubIndex(i2, Not(Not(r"")))) == names(i)
    @test DataFrames._names(SubIndex(i2, Not(Not(r"x1.")))) == [:x12, :x131]
    @test isempty(DataFrames._names(SubIndex(i2, Not(Not(r"xx")))))
    @test DataFrames._names(SubIndex(i2, Not(Not(r"")))) == names(i2)
    @test DataFrames.parentcols(SubIndex(i2, Not(Not(r"x1.")))) == [2, 3]
    @test isempty(DataFrames.parentcols(SubIndex(i2, Not(Not(r"xx")))))
    @test DataFrames.parentcols(SubIndex(i2, Not(Not(r"")))) == 1:5

    i3 = SubIndex(i, Not(Not(r"x1.")))
    @test i3[Not(Not(r"x1.$"))] == [1]
    @test isempty(i3[Not(Not(r"xx"))])
    @test i3[Not(Not(r""))] == 1:2
    @test names(SubIndex(i3, Not(Not(r"x1.$")))) == [:x12]
    @test isempty(names(SubIndex(i3, Not(Not(r"xx")))))
    @test names(SubIndex(i3, Not(Not(r"")))) == names(i3)
    @test DataFrames._names(SubIndex(i3, Not(Not(r"x1.$")))) == [:x12]
    @test isempty(DataFrames._names(SubIndex(i3, Not(Not(r"xx")))))
    @test DataFrames._names(SubIndex(i3, Not(Not(r"")))) == names(i3)
    @test DataFrames.parentcols(SubIndex(i3, Not(Not(r"x1.$")))) == [1]
    @test isempty(DataFrames.parentcols(SubIndex(i3, Not(Not(r"xx")))))
    @test DataFrames.parentcols(SubIndex(i3, Not(Not(r"")))) == 1:2
end

@testset "Between indexing" begin
    df = DataFrame(a=1, b=2, c=3)
    @test select(df, Between(1,2)) == df[:, 1:2]
    @test select(df, Between(1,:b)) == df[:, 1:2]
    @test select(df, Between(:a,2)) == df[:, 1:2]
    @test select(df, Between(:a,:b)) == df[:, 1:2]
    @test select(df, Between(2,1)) == df[:, 2:1]
    @test select(df, Between(:b,1)) == df[:, 2:1]
    @test select(df, Between(2,:a)) == df[:, 2:1]
    @test select(df, Between(:b,:a)) == df[:, 2:1]

    @test df[:, Between(1,2)] == df[:, 1:2]
    @test df[:, Between(1,:b)] == df[:, 1:2]
    @test df[:, Between(:a,2)] == df[:, 1:2]
    @test df[:, Between(:a,:b)] == df[:, 1:2]
    @test df[:, Between(2,1)] == df[:, 2:1]
    @test df[:, Between(:b,1)] == df[:, 2:1]
    @test df[:, Between(2,:a)] == df[:, 2:1]
    @test df[:, Between(:b,:a)] == df[:, 2:1]

    @test_throws BoundsError df[:, Between(:b,0)]
    @test_throws BoundsError df[:, Between(0,:b)]
    @test_throws ArgumentError df[:, Between(:b,:z)]
    @test_throws ArgumentError df[:, Between(:z,:b)]
end

@testset "All indexing" begin
    df = DataFrame(a=1, b=2, c=3)
    @test select(df, All()) == df[:, :]
    @test df[:, All()] == df[:, :]

    @test select(df, All(1,2)) == df[:, 1:2]
    @test select(df, All(1,:b)) == df[:, 1:2]
    @test select(df, All(:a,2)) == df[:, 1:2]
    @test select(df, All(:a,:b)) == df[:, 1:2]
    @test select(df, All(2,1)) == df[:, [2,1]]
    @test select(df, All(:b,1)) == df[:, [2,1]]
    @test select(df, All(2,:a)) == df[:, [2,1]]
    @test select(df, All(:b,:a)) == df[:, [2,1]]

    @test df[:, All(1,2)] == df[:, 1:2]
    @test df[:, All(1,:b)] == df[:, 1:2]
    @test df[:, All(:a,2)] == df[:, 1:2]
    @test df[:, All(:a,:b)] == df[:, 1:2]
    @test df[:, All(2,1)] == df[:, [2,1]]
    @test df[:, All(:b,1)] == df[:, [2,1]]
    @test df[:, All(2,:a)] == df[:, [2,1]]
    @test df[:, All(:b,:a)] == df[:, [2,1]]

    @test df[:, All(1,1,2)] == df[:, 1:2]
    @test df[:, All(:a,1,:b)] == df[:, 1:2]
    @test df[:, All(:a,2,:b)] == df[:, 1:2]
    @test df[:, All(:a,:b,2)] == df[:, 1:2]
    @test df[:, All(2,1,:a)] == df[:, [2,1]]

    df = DataFrame(a1=1, a2=2, b1=3, b2=4)
    @test df[:, All(r"a", Not(r"1"))] == df[:, [1,2,4]]
    @test df[:, All(Not(r"1"), r"a")] == df[:, [2,4,1]]
end

end # module
