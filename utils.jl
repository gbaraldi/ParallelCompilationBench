using Serialization

macro my_time(ex)
    quote
        local result

        local start_time = time_ns()
        local end_time = start_time
        try
            local val = $(esc(ex))
            end_time = time_ns()
            result = (;
                times = (end_time - start_time),
            )
        catch e
            @show e
            result = (;
                times = NaN,
            )
        end

        #run(`ps uxww`)
        #run(`pmap $(getpid())`)

        if "SERIALIZE" in ARGS
            # uglyness to communicate over non stdout (specifically file descriptor 3)
            @invokelatest serialize(open(RawFD(3)), result)
        else
            @invokelatest display("test took $(result.times/1e9) seconds")
        end
    end
end

function display_if(arg)
    if "SERIALIZE" in ARGS
        nothing
    else
        @invokelatest display(arg)
    end
end