const p1 = Val(200)
const p2 = Val(200)
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

Ptr{Val(0)}()

func = eval(gencode(0))

@time invokelatest(func, 1, p1, p2)

start = time_ns()
invokelatest(func, Ptr{Val(0)}, p1, p2)
finish = time_ns()
total = (finish - start) / 1e9
display("Time: $total seconds")