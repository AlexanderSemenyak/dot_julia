[![Build Status](https://travis-ci.org/jmboehm/RegressionTables.jl.svg?branch=master)](https://travis-ci.org/jmboehm/RegressionTables.jl) [![Coverage Status](https://coveralls.io/repos/jmboehm/RegressionTables.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/jmboehm/RegressionTables.jl?branch=master) [![codecov.io](http://codecov.io/github/jmboehm/RegressionTables.jl/coverage.svg?branch=master)](http://codecov.io/github/jmboehm/RegressionTables.jl?branch=master)

## RegressionTables.jl

This package provides publication-quality regression tables for use with [FixedEffectModels.jl](https://github.com/matthieugomez/FixedEffectModels.jl) and [GLM.jl](https://github.com/JuliaStats/GLM.jl).

In its objective it is similar to  (and heavily inspired by) the Stata command [`esttab`](http://repec.sowi.unibe.ch/stata/estout/esttab.html) and the R package [`stargazer`](https://cran.r-project.org/web/packages/stargazer/).

To install the package, type in the Julia command prompt

```julia
Pkg.add("RegressionTables")
```

## A brief demonstration

```julia
using RegressionTables, DataFrames, FixedEffectModels, RDatasets

df = dataset("datasets", "iris")
df[:SpeciesDummy] = categorical(df[:Species])

rr1 = reg(df, @model(SepalLength ~ SepalWidth   , fe = SpeciesDummy))
rr2 = reg(df, @model(SepalLength ~ SepalWidth + PetalLength   , fe = SpeciesDummy))
rr3 = reg(df, @model(SepalLength ~ SepalWidth + PetalLength + PetalWidth  , fe = SpeciesDummy))
rr4 = reg(df, @model(SepalWidth ~ SepalLength + PetalLength + PetalWidth  , fe = SpeciesDummy))

regtable(rr1,rr2,rr3,rr4; renderSettings = asciiOutput())
```
yields
```
----------------------------------------------------------
                         SepalLength            SepalWidth
               ------------------------------   ----------
                    (1)        (2)        (3)          (4)
----------------------------------------------------------
SepalWidth     0.804***   0.432***   0.496***             
                (0.106)    (0.081)    (0.086)             
PetalLength               0.776***   0.829***      -0.188*
                           (0.064)    (0.069)      (0.083)
PetalWidth                            -0.315*     0.626***
                                      (0.151)      (0.123)
SepalLength                                       0.378***
                                                   (0.066)
----------------------------------------------------------
SpeciesDummy        Yes        Yes        Yes          Yes
----------------------------------------------------------
Estimator           OLS        OLS        OLS          OLS
----------------------------------------------------------
N                   150        150        150          150
R2                0.726      0.863      0.867        0.635
----------------------------------------------------------
```
LaTeX output can be generated by using
```julia
regtable(rr1,rr2,rr3,rr4; renderSettings = latexOutput())
```
which yields
```
\begin{tabular}{lrrrr}
\toprule
             & \multicolumn{3}{c}{SepalLength} & \multicolumn{1}{c}{SepalWidth} \\
\cmidrule(lr){2-4} \cmidrule(lr){5-5}
             &      (1) &      (2) &       (3) &                            (4) \\
\midrule
SepalWidth   & 0.804*** & 0.432*** &  0.496*** &                                \\
             &  (0.106) &  (0.081) &   (0.086) &                                \\
PetalLength  &          & 0.776*** &  0.829*** &                        -0.188* \\
             &          &  (0.064) &   (0.069) &                        (0.083) \\
PetalWidth   &          &          &   -0.315* &                       0.626*** \\
             &          &          &   (0.151) &                        (0.123) \\
SepalLength  &          &          &           &                       0.378*** \\
             &          &          &           &                        (0.066) \\
\midrule
SpeciesDummy &      Yes &      Yes &       Yes &                            Yes \\
\midrule
Estimator    &      OLS &      OLS &       OLS &                            OLS \\
\midrule
$N$          &      150 &      150 &       150 &                            150 \\
$R^2$        &    0.726 &    0.863 &     0.867 &                          0.635 \\
\bottomrule
\end{tabular}
```
Similarly, HTML tables can be created with `htmlOutput()`.

Send the output to a text file by passing the destination file string to the `asciiOutput()`, `latexOutput()`, or `htmlOutput()` functions:
```julia
regtable(rr1,rr2,rr3,rr4; renderSettings = latexOutput("myoutputfile.tex"))
```
then use `\input` in LaTeX to include that file in your code. Be sure to use the `booktabs` package:
```latex
\documentclass{article}
\usepackage{booktabs}

\begin{document}

\begin{table}
\label{tab:mytable}
\input{myoutputfile}
\end{table}

\end{document}
```

`regtable()` can also print `DataFrameRegressionModel`'s from [GLM.jl](https://github.com/JuliaStats/GLM.jl):
```julia
dobson = DataFrame(Counts = [18.,17,15,20,10,20,25,13,12],
    Outcome = pool(repeat(["A", "B", "C"], outer = 3)),
    Treatment = pool(repeat(["a","b", "c"], inner = 3)))
lm1 = fit(LinearModel, @formula(SepalLength ~ SepalWidth), df)
gm1 = fit(GeneralizedLinearModel, @formula(Counts ~ 1 + Outcome + Treatment), dobson,
                  Poisson())

regtable(rr1,lm1,gm1; renderSettings = asciiOutput())
```
yields
```
---------------------------------------------
                   SepalLength        Counts
               -------------------   --------
                    (1)        (2)        (3)
---------------------------------------------
(Intercept)    6.526***   6.526***   3.045***
                (0.479)    (0.479)    (0.171)
SepalWidth       -0.223     -0.223           
                (0.155)    (0.155)           
Outcome: B                             -0.454
                                      (0.202)
Outcome: C                             -0.293
                                      (0.193)
Treatment: b                            0.000
                                      (0.200)
Treatment: c                            0.000
                                      (0.200)
---------------------------------------------
Estimator           OLS        OLS         NL
---------------------------------------------
N                   150        150          9
R2                0.014      0.014           
---------------------------------------------
```

## Options

### Function Arguments
* `rr::rr::Union{AbstractRegressionResult,DataFrames.DataFrameRegressionModel}...` are the `AbstractRegressionResult`s from `FixedEffectModels.jl` (or `DataFrameRegressionModel`s from `GLM.jl`) that should be printed. Only required argument.
* `regressors` is a `Vector` of regressor names (`String`s) that should be shown, in that order. Defaults to an empty vector, in which case all regressors will be shown.
* `fixedeffects` is a `Vector` of FE names (`String`s) that should be shown, in that order. Defaults to an empty vector, in which case all FE's will be shown.
* `labels` is a `Dict` that contains displayed labels for variables (strings) and other text in the table. If no label for a variable is found, it default to variable names. See documentation for special values.
* `estimformat` is a `String` that describes the format of the estimate. Defaults to "%0.3f".
* `estim_decoration` is a `Function` that takes the formatted string and the p-value, and applies decorations (such as the beloved stars). Defaults to (* p<0.05, ** p<0.01, *** p<0.001).
* `statisticformat` is a `String` that describes the format of the number below the estimate (se/t). Defaults to "%0.4f".
* `below_statistic` is a `Symbol` that describes a statistic that should be shown below each point estimate. Recognized values are `:blank`, `:se`, and `:tstat`. Defaults to `:se`.
* `below_decoration` is a `Function` that takes the formatted statistic string, and applies a decorations. Defaults to round parentheses.
* `regression_statistics` is a `Vector` of `Symbol`s that describe statistics to be shown at the bottom of the table. Recognized symbols are `:nobs`, `:r2`, `:r2_a`, `:r2_within`, `:f`, `:p`, `:f_kp`, `:p_kp`, and `:dof`. Defaults to `[:nobs, :r2]`.
* `number_regressions` is a `Bool` that governs whether regressions should be numbered. Defaults to `true`.
* `number_regressions_decoration` is a `Function` that governs the decorations to the regression numbers. Defaults to `s -> "($s)"`.
* `print_fe_section` is a `Bool` that governs whether a section on fixed effects should be shown. Defaults to `true`.
* `print_estimator_section`  is a `Bool` that governs whether to print a section on which estimator (OLS/IV) is used. Defaults to `true`.
* `standardize_coef` is a `Bool` that governs whether the table should show standardized coefficients. Note that this only works with `DataFrameRegressionModel`s, and that only coefficient estimates and the `below_statistic` are being standardized (i.e. the R^2 etc still pertain to the non-standardized regression).
* `out_buffer` is an `IOBuffer` that the output gets sent to (unless an output file is specified, in which case the output is only sent to the file).
* `renderSettings::RenderSettings` is a `RenderSettings` composite type that governs how the table should be rendered. Standard supported types are ASCII (via `asciiOutput(outfile::String)`) and LaTeX (via `latexOutput(outfile::String)`). If no argument to these two functions are given, the output is sent to STDOUT. Defaults to ASCII with STDOUT.
* `transform_labels` is a function that is used to transform labels. For example, in order to escape certain LaTeX characters, use
    ```julia
    repl_dict = Dict("&" => "\\&", "%" => "\\%", "\$" => "\\\$", "#" => "\\#", "_" => "\\_", "{" => "\\{", "}" => "\\}") 
    function transform(s, repl_dict=repl_dict)
        for (old, new) in repl_dict
            s = replace.(s, Ref(old => new))
        end
        s
    end
    
    regtable(rr; renderSettings = latexOutput(), transform_labels = transform)
    ```
    Defaults to `identity`. The most common use case is probably to escape the ampersand `&` in LaTeX, which is already implemented as `transform_labels = escape_ampersand`.


### Label Codes

The following is the exhaustive list of strings that govern the output of labels. Use e.g.
```julia
labels = Dict("__LABEL_STATISTIC_N__" => "Number of observations")
```
to change the label for the row showing the number of observations in each regression.

* `__LABEL_ESTIMATOR__` (default: "Estimator")
* `__LABEL_ESTIMATOR_OLS__` (default: "OLS")
* `__LABEL_ESTIMATOR_IV__` (default: "IV")
* `__LABEL_ESTIMATOR_NL__` (default: "NL")

* `__LABEL_FE_YES__` (default: "Yes")
* `__LABEL_FE_NO__` (default: "")

* `__LABEL_STATISTIC_N__` (default: "N" in `asciiOutput()`)
* `__LABEL_STATISTIC_R2__` (default: "R2" in `asciiOutput()`)
* `__LABEL_STATISTIC_R2_A__` (default: "Adjusted R2" in `asciiOutput()`)
* `__LABEL_STATISTIC_R2_WITHIN__` (default: "Within-R2" in `asciiOutput()`)
* `__LABEL_STATISTIC_F__` (default: "F" in `asciiOutput()`)
* `__LABEL_STATISTIC_P__` (default: "F-test p value" in `asciiOutput()`)
* `__LABEL_STATISTIC_F_KP__` (default: "First-stage F statistic" in `asciiOutput()`)
* `__LABEL_STATISTIC_P_KP__` (default: "First-stage p value" in `asciiOutput()`)
* `__LABEL_STATISTIC_DOF__` (default: "Degrees of Freedom" in `asciiOutput()`)
