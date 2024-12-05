# Compiles one method with many method instances, all threads on the same method
# This stresses MI insertion

# These values can be much larger on master (around 200) since compiling this code has gotten much faster
include("../utils.jl")
const p1 = Val(10)
const p2 = Val(10)

f(::Val{X}) where X = X

function gencode(i::Integer)
    fname = Symbol("get_t$i")
    quote
        function $fname(t, v1::Val, v2::Val)
            V1 = f(v1)
            V2 = f(v2)
            V1 != 0 && V2 != 0 && return $fname($fname(t, Val(V1 - 1), v2), v1, Val(V2 - 1))
            V1 != 0 && return $fname(t, Val(V1 - 1), v2)
            V2 != 0 && return $fname(t, v1, Val(V2 - 1))
            return t
        end
    end
end

threads = Threads.nthreads()

ptimes = zeros(UInt64, threads)

Threads.@threads :static for i in 1:threads
    Ptr{Val(i)}()
end

f0 = eval(gencode(0))
invokelatest(f0, t, p1, p2)

display_if("Finished all setup work")

function work(fs, p1, p2)
    Threads.@threads for i in 1:threads
        t = Ptr{Val{i+threads}}()
        local start = time_ns()
        invokelatest(f0, t, p1, p2)
        ptimes[i] = time_ns() - start
    end
end

@my_time work(fs, p1, p2)

display_if("Finished all work")

max_t = 0
for i in 1:threads
    global max_t
    time_t = ptimes[i] / 1e9
    if time_t > max_t
        max_t = time_t
    end
    time = ptimes[i] / 1e9
    display_if("Thread $i took $time seconds")
end

