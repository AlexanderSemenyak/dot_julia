import DataFrames

df = DataFrames.DataFrame()
df[:a] = ["a", "b", "c"]
df[:b] = [1, 2, 3]
df[:c] = ["d", "e", "f"]
df[:d] = [4.0, 5.0, 6.0]
Test.@test(ClassImbalance.factor_columns(df) == [1, 3])

a = ["a", "b", "a"]
b = ClassImbalance.factor_to_float(a)
c = ClassImbalance.float_to_factor(b, ["a", "b"])
Test.@test(all(a .== c))
