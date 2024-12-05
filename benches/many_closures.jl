# This compiles lots of closures which seem to stress the codegen lock, and specifically
# with inference being parallel the LLVM lock
include("../utils.jl")
function bench()
    N = 10000
    out = Vector{Int}(undef, N);
    @sync for i in 1:N
        Threads.@spawn begin
            f = @eval (x) -> x + $i
            v = @eval $f(1)
            out[i] = v
        end
    end
    @assert sum(out) == sum(1:N) + N
end

@my_time bench()
