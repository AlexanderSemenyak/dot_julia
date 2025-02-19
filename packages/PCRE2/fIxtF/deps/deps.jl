## This file autogenerated by BinaryProvider.write_deps_file().
## Do not edit.
##
## Include this file within your main top-level source, and call
## `check_deps()` from within your module's `__init__()` method

if isdefined((@static VERSION < v"0.7.0-DEV.484" ? current_module() : @__MODULE__), :Compat)
    import Compat.Libdl
elseif VERSION >= v"0.7.0-DEV.3382"
    import Libdl
end
const libpcre2_8 = joinpath(dirname(@__FILE__), "usr/lib/libpcre2-8.so")
const libpcre2_16 = joinpath(dirname(@__FILE__), "usr/lib/libpcre2-16.so")
const libpcre2_32 = joinpath(dirname(@__FILE__), "usr/lib/libpcre2-32.so")
function check_deps()
    global libpcre2_8
    if !isfile(libpcre2_8)
        error("$(libpcre2_8) does not exist, Please re-run Pkg.build(\"PCRE2\"), and restart Julia.")
    end

    if Libdl.dlopen_e(libpcre2_8) in (C_NULL, nothing)
        error("$(libpcre2_8) cannot be opened, Please re-run Pkg.build(\"PCRE2\"), and restart Julia.")
    end

    global libpcre2_16
    if !isfile(libpcre2_16)
        error("$(libpcre2_16) does not exist, Please re-run Pkg.build(\"PCRE2\"), and restart Julia.")
    end

    if Libdl.dlopen_e(libpcre2_16) in (C_NULL, nothing)
        error("$(libpcre2_16) cannot be opened, Please re-run Pkg.build(\"PCRE2\"), and restart Julia.")
    end

    global libpcre2_32
    if !isfile(libpcre2_32)
        error("$(libpcre2_32) does not exist, Please re-run Pkg.build(\"PCRE2\"), and restart Julia.")
    end

    if Libdl.dlopen_e(libpcre2_32) in (C_NULL, nothing)
        error("$(libpcre2_32) cannot be opened, Please re-run Pkg.build(\"PCRE2\"), and restart Julia.")
    end

end
