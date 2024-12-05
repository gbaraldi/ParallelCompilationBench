const doc = """run_benchmarks.jl -- Parallel compilation
Usage:
    run_benchmarks.jl [options]
    run_benchmarks.jl -h | --help
    run_benchmarks.jl --version
Options:
    -n <runs>, --runs=<runs>              Number of runs for each benchmark [default: 10].
    -t <threads>, --threads=<threads>     Number of threads to use [default: 1].
    -s <max>, --scale=<max>               Maximum number of threads for scaling test.
    -h, --help                            Show this screen.
    --version                             Show version.
    --json                                Serializes output to `json` file
"""

using DocOpt
using JSON
using PrettyTables
using Printf
using Serialization
using Statistics
using TypedTables
using CSV

const args = docopt(doc, version = v"0.1.0")
const JULIAVER = Base.julia_cmd()[1]

# times in ns
# TODO: get better stats
function get_stats(times::Vector)
    return [minimum(times), median(times), maximum(times), std(times)]
end

"""
    Highlights cells in a column based on value
        green if less than lo
        yellow if between lo and hi
        red if above hi
"""
function highlight_col(col, lo, hi)
    [Highlighter((data,i,j) -> (j == col) && data[i, j] <= lo; foreground=:green),
     Highlighter((data,i,j) -> (j == col) && lo < data[i, j] < hi; foreground=:yellow),
     Highlighter((data,i,j) -> (j == col) && hi <= data[i, j]; foreground=:red),]
end



function run_bench(runs, threads, file, show_json = false)
    times = []
    for _ in 1:runs
        # uglyness to communicate over non stdout (specifically file descriptor 3)
        p = Base.PipeEndpoint()
        cmd = `$JULIAVER --project=. --threads=$threads $file SERIALIZE`
        cmd = run(Base.CmdRedirect(cmd, p, 3), stdin, stdout, stderr, wait=false)
        r = deserialize(p)
        @assert success(cmd)
        # end uglyness
        push!(times, r.times)
    end

    data = Table(
        time = times,
        file = [file for _ in 1:runs],
        threads = [threads for _ in 1:runs],
        version = [string(Base.VERSION) for _ in 1:runs],
    )
    results = joinpath(@__DIR__, "results$VERSION.csv")
    CSV.write(results, data; append=isfile(results))
    total_stats = get_stats(times) ./ 1_000_000
    header = (["", "total time"],
              ["", "ms"])
    labels = ["minimum", "median", "maximum", "stdev"]
    if show_json
        data = Dict([("total time", total_stats)])
        JSON.print(data)
    else
        data = hcat(labels, total_stats)
        pretty_table(data; header, formatters=ft_printf("%0.0f"))
    end
end

function run_category_files(benches, args, show_json = false)
    local runs = parse(Int, args["--runs"])
    local threads = parse(Int, args["--threads"])
    local max = if isnothing(args["--scale"]) 0 else parse(Int, args["--scale"]) end
    for bench in benches
        if !show_json
            @show bench
        end
        if isnothing(args["--scale"])
            run_bench(runs, threads, bench, show_json)
        else
            local n = 0
            while true
                threads = 2^n
                threads > max && break
                @show (threads)
                run_bench(runs, threads, bench, show_json)
                n += 1
            end
        end
    end
end

function run_all_benches(args, show_json = false)
    benches = filter(f -> endswith(f, ".jl"), readdir())
    run_category_files(benches, args, show_json)
    cd("..")
end

function main(args)
    rm("results$VERSION.csv", force=true)
    cd(joinpath(@__DIR__, "benches"))
    show_json = args["--json"]
    # validate choices
    if !isnothing(args["--scale"])
        @assert args["--threads"] == "1" "Specify either --scale or --threads."
    end

    run_all_benches(args, show_json)
end

main(args)
