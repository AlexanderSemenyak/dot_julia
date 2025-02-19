Examples
========

```@meta
CurrentModule = PrettyTables
DocTestSetup = quote
    using PrettyTables
end
```

In the following, it is presented how the following matrix can be printed using
this package:

```julia-repl
julia> data = Any[ 1    false      1.0     0x01 ;
                   2     true      2.0     0x02 ;
                   3    false      3.0     0x03 ;
                   4     true      4.0     0x04 ;
                   5    false      5.0     0x05 ;
                   6     true      6.0     0x06 ;]
```

![](../assets/ex_00001.png)

![](../assets/ex_00002.png)

![](../assets/ex_00003.png)

![](../assets/ex_00004.png)

![](../assets/ex_00005.png)

The following example indicates how `highlighters` can be used to highlight the
lowest and highest element in the data considering the columns 1, 3, and 5:

![](../assets/ex_00006.png)

Since this package has support to the API defined by
[Tables.jl](https://github.com/JuliaData/Tables.jl), then many formats, *e.g*
[DataFrames.jl](https://github.com/JuliaData/DataFrames.jl), can be pretty
printed:

![](../assets/ex_00007.png)

You can use `hlines` keyword to divide the table into interesting parts:

![](../assets/ex_00008.png)

If you want to break lines inside the cells, then you can set the keyword
`linebreaks` to `true`. Hence, the characters `\n` will cause a line break
inside the cell.

![](../assets/ex_00009.png)

The keyword `noheader` can be used to suppres the header, which leads to a very
simplistic, compact format.

![](../assets/ex_00010.png)

In the following, it is shown how the filters can be used to print only the even
rows and columns:

![](../assets/ex_00011.png)

By default, if the data is larger than the screen, then it will be cropped to
fit it. This can be changed by using the keywords `crop` and `screen_size`.

![](../assets/ex_00012.png)

If you want to save the printed table to a file, you can do:

```julia-repl
julia> open("output.txt", "w") do f
            pretty_table(f,data)
       end
```
