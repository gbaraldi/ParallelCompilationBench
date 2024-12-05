# A somewhat representative benchmark for compilation times at RelationalAI.
# Run the benchmark with varying number of threads, to measure thread scaling.
# For example, on my macbook pro M2:
#  $ julia -t1 ~/Downloads/specializing-trees.jl
#   1.361154 seconds (6.29 M allocations: 654.535 MiB, 5.00% gc time, 81.84% compilation time)
#  41.391592 seconds (6.61 M allocations: 720.834 MiB, 0.14% gc time, 99.79% compilation time)
#  $ julia -t2 ~/Downloads/specializing-trees.jl
#   1.220264 seconds (6.36 M allocations: 659.236 MiB, 3.62% gc time, 175.68% compilation time)
#  40.774872 seconds (6.65 M allocations: 723.694 MiB, 0.08% gc time, 199.20% compilation time)
#  $ julia -t4 ~/Downloads/specializing-trees.jl
#   1.287302 seconds (6.53 M allocations: 670.671 MiB, 2.84% gc time, 369.89% compilation time)
#  40.906825 seconds (6.78 M allocations: 732.149 MiB, 0.07% gc time, 390.31% compilation time)
#  $ julia -t8 ~/Downloads/specializing-trees.jl
#   1.545116 seconds (6.66 M allocations: 679.279 MiB, 2.85% gc time, 755.79% compilation time)
#  43.464048 seconds (6.89 M allocations: 739.796 MiB, 0.04% gc time, 680.64% compilation time)

# ------------------------------------------------

# A query plan, represented as a tree, with the full plan specified
# in the type domain. We specialize an instance of this query plan
# tree to represent a query.
include("../utils.jl")
struct MaterializedRelation{T}
    tuples::Vector{T}
end

function _construct_cartprod end  # Support slurping constructor: Union(a,b,c)
struct CartProduct{RTuple}
    relations::RTuple
    @__MODULE__()._construct_cartprod(t::RTuple) where RTuple = new{RTuple}(t)
end
CartProduct(relations...) = _construct_cartprod((relations...,))
function _construct_union end  # Support slurping constructor: Union(a,b,c)
struct Union{RTuple}
    relations::RTuple
    @__MODULE__()._construct_union(t::RTuple) where RTuple = new{RTuple}(t)
end
Union(relations...) = _construct_union((relations...,))

struct Projection{SelectionTuple, R}
    relation::R
end
Projection{SelectionTuple}(r::R) where {SelectionTuple, R} = Projection{SelectionTuple, R}(r)

struct Filter{Predicate, R}
    relation::R
end
Filter{Predicate}(r::R) where {Predicate, R} = Filter{Predicate, R}(r)
Filter(pred, r::R) where {R} = Filter{pred, R}(r)

struct Unique{R}
    relation::R
end

# ----- iterate(query_plan) -----------------------------

function iterate(r::MaterializedRelation)
    return r.tuples
end

function iterate(r::Projection{S}) where S
    positions = S::Tuple{Vararg{Int}}
    return [project(tup, positions...) for tup in iterate(r.relation)]
end
project(tup) = ()
project(tup, i, positions...) = (tup[i], project(tup, positions...)...)

function iterate(r::CartProduct{RTuple}) where {RTuple}
    streams = Tuple(iterate(r) for r in r.relations)
    return product(streams)
end
concat() = ()
concat(tup1) = (tup1...,)
concat(tup1, tup2, tuples...) = concat((tup1..., tup2...), tuples...)
function product(relations)
    OutType = Tuple{Iterators.flatten(fieldtypes.(eltype.(relations)))...}
    any(isempty.(relations)) && return OutType[]
    L = length(relations)
    lengths = NTuple{L,Int}(length(r) for r in relations)
    len = Base.prod(lengths)
    out = Vector{OutType}(undef, len)

    current = 1
    iterators = [1 for _ in relations]

    for i in 1:len
        tup = concat((relations[j][iterators[j]] for j in 1:length(relations))...)
        out[i] = tup

        iterators[1] += 1
        # Carry the one (overflow right)
        for j in 1:length(iterators)-1
            if iterators[j] > lengths[j]
                iterators[j] = 1
                iterators[j+1] += 1
            end
        end
    end

    return out
end


function iterate(r::Union{RTuple}) where {RTuple}
    return vcat((iterate(r) for r in r.relations)...)
end

function iterate(r::Filter{Predicate}) where Predicate
    return [tup for tup in iterate(r.relation) if Predicate(tup)]
end

function iterate(r::Unique)
    return unique(iterate(r.relation))
end


# -----------------------------------
# ----- benchmarks ------------------
# -----------------------------------

function test1()
    p = Projection{(1, 2)}(MaterializedRelation([(10, 20, 30), (100, 200, 300)]))
    u = Union(p, p)
    c = CartProduct(u, p, u)
    c = Unique(c)
    u = Union(c, c, c)
    u = Union(u)
    u = Unique(u)
    c = CartProduct(u)
    r = Filter(((a,b,c,d,e,f)::Tuple) -> a+b+c+d+e+f > 800, c)
    return r
end
function test2()
    p = Projection{(1, 3)}(MaterializedRelation([(10, 20, 30), (100, 200, 300)]))
    u = Union(p, p)
    c = CartProduct(u, p, u)
    r = Projection{(1, 2)}(c)
    r = Unique(r)
    r = CartProduct(r, r)
    r = Projection{(1, 2)}(r)
    r = Filter((tup) -> sum(tup) > 300, r)
    r = Unique(r)
    r = CartProduct(r, r, r, r, r)
    r = Union(r, r)
    r = Projection{(1, 2, 3)}(r)
    r = Unique(r)
    r = CartProduct(r, r)
    r = Projection{(1, 2, 3)}(r)
    r = Unique(r)
    r = Union(r, r)
    return r
end
# Tuned by hand to something roughly expensive enough to make this benchmark worthwhile.
function test_construct_N(n_projs, n_carts)
    r = Projection{(1,)}(MaterializedRelation([(1,), (2,), (3,)]))
    r = CartProduct(r,r,r,r,r,r)
    for i in 1:n_projs
        r = Projection{(1,)}(r)
    end
    r = Unique(r)
    for i in 1:n_carts
        r = CartProduct(r, r, r)
    end
    r = CartProduct(r)
    r = Filter((tup) -> all(==(1), tup), r)
    r = Unique(r)
    # Note: At the end here, compilation time is very sensitive to each (r,r), since
    # we're doubling the size of the type each time.
    r = Union(r, r)
    r = CartProduct(r, r)
    r = Projection{(1,2)}(r)
    r = Unique(r)
    return r
end


function parallel_bench()
    results = Vector{Any}(undef, 1000)
    # Splitting these out into functions makes the profile more clear:
    bench1!(results)
    bench2!(results)
end
# Same 2 queries lots and lots of times in parallel. (Can't parallelize more than 2x.)
bench1!(results) = @sync for _ in 1:1000
    Threads.@spawn results[1] = @eval iterate($(test1()))
    Threads.@spawn results[2] = @eval iterate($(test2()))
end
# Lots of different queries in different threads
bench2!(results) = @sync for i in 1:20
    Threads.@spawn begin
        # inferencebarrier simulates user input - we can't compile ahead of time
        r = Base.inferencebarrier(test_construct_N)(i, 2)
        results[i] = iterate(r)
    end
end

if !Base.isinteractive()
    @my_time parallel_bench()
end