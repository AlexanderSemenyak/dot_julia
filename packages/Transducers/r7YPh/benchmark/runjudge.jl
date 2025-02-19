using PkgBenchmark

mkconfig(; kwargs...) =
    BenchmarkConfig(
        env = Dict(
            "JULIA_NUM_THREADS" => "1",
            "OMP_NUM_THREADS" => "1",
        );
        kwargs...
    )

group_target = benchmarkpkg(
    dirname(@__DIR__),
    mkconfig(),
    resultfile = joinpath(@__DIR__, "result-target.json"),
)

group_baseline = benchmarkpkg(
    dirname(@__DIR__),
    mkconfig(id = "master"),
    resultfile = joinpath(@__DIR__, "result-baseline.json"),
)

judgement = judge(group_target, group_baseline)
