function bench()
    N = 10000
    out = Vector{Int}(undef, N);
    @time @sync for i in 1:N
        Threads.@spawn begin
            f = @eval (x) -> x + $i
            v = @eval $f(1)
            out[i] = v
        end
    end
    @assert sum(out) == sum(1:N) + N
end

bench()
