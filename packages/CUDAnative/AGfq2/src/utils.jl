# logging

using Logging

# fatal versions to `@error`, including a safe version for compile-time errors
# (to be used instead of `error`, which _emits_ an error)
macro fatal(ex...)
    esc(quote
        @error $(ex...)
        error("Fatal error occurred")
    end)
end

# define safe loggers for use in generated functions (where task switches are not allowed)
for level in [:trace, :debug, :info, :warn, :error, :fatal]
    @eval begin
        macro $(Symbol("safe_$level"))(ex...)
            macrocall = :(@placeholder $(ex...))
            # NOTE: `@placeholder` in order to avoid hard-coding @__LINE__ etc
            macrocall.args[1] = Symbol($"@$level")
            quote
                old_logger = global_logger()
                global_logger(Logging.ConsoleLogger(Core.stderr, old_logger.min_level))
                ret = $(esc(macrocall))
                global_logger(old_logger)
                ret
            end
        end
    end
end


# device capability handling

# select the highest capability that is supported by both the toolchain and device
function supported_capability(dev::CuDevice)
    dev_cap = capability(dev)
    compat_caps = filter(cap -> cap <= dev_cap, target_support)
    isempty(compat_caps) &&
        error("Device capability v$dev_cap not supported by available toolchain")

    return maximum(compat_caps)
end

# return the capability of the current context's device, or a sane fall-back
function current_capability()
    if initialized[]
        return supported_capability(device())
    else
        # newer devices tend to support cleaner code (higher-level instructions, etc)
        # so target the most recent device as supported by this toolchain
        return maximum(target_support)
    end
end
