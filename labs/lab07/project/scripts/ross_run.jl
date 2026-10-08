using DrWatson
@quickactivate "project"      
using Statistics, DataFrames, Plots, CSV
include(srcdir("ross.jl"))

params = Dict(
    :N => [3, 5, 10],
    :S => [1, 2, 3],
    :nrepair => [1, 2],
    :mttf => 100.0,
    :mttr => 1.0,
    :seed => collect(1:5),
)

rows = NamedTuple[]
for p in dict_list(params)
    println("RUN: N=$(p[:N])")
    data, _ = produce_or_load(p, datadir("sims", "ross"); prefix = "ross") do p
        run_ross(; p...)
    end
    push!(rows, (N = p[:N], S = p[:S], nrepair = p[:nrepair], seed = p[:seed],
                 T = data["T"], util = data["util"], Lq = data["Lq"]))
end
df = DataFrame(rows)

# Усреднение по повторам и сравнение с аналитикой
summary = combine(groupby(df, [:N, :S, :nrepair]),
                  :T => mean => :T_sim,
                  :T => (x -> std(x) / sqrt(length(x))) => :T_se,
                  :util => mean => :util,
                  :Lq => mean => :Lq)
summary.T_ana = [ross_analytic(; N = r.N, S = r.S, nrepair = r.nrepair,
                               mttf = 100.0, mttr = 1.0) for r in eachrow(summary)]
sort!(summary, [:N, :nrepair, :S])
println(summary)
CSV.write(datadir("ross_summary.csv"), summary)

# График 1: время до падения, имитация и аналитика (N = 10, один ремонтник)
sub = filter(r -> r.N == 10 && r.nrepair == 1, summary)
p1 = plot(sub.S, sub.T_sim; yerror = 1.96 .* sub.T_se, marker = :o,
          label = "имитация", yscale = :log10,
          xlabel = "число запасных S", ylabel = "E[T], часы")
plot!(p1, sub.S, sub.T_ana; marker = :s, label = "аналитика")
wsave(plotsdir("ross_crash_time.png"), p1)

# График 2: влияние числа ремонтников на время до падения (N = 10)
p2 = plot(xlabel = "число запасных S", ylabel = "E[T], часы", yscale = :log10)
for r in 1:2
    s = filter(x -> x.N == 10 && x.nrepair == r, summary)
    plot!(p2, s.S, s.T_sim; marker = :o, label = "ремонтников: $r")
end
wsave(plotsdir("ross_repairmen.png"), p2)

# График 3: загрузка ремонтника и средняя длина очереди (N = 10)
s1 = filter(x -> x.N == 10, summary)
labels = ["S=$(r.S), r=$(r.nrepair)" for r in eachrow(s1)]
p3 = bar(labels, s1.util; ylabel = "загрузка ремонтника", legend = false,
         xrotation = 45)
p4 = bar(labels, s1.Lq; ylabel = "средняя длина очереди", legend = false,
         xrotation = 45)
wsave(plotsdir("ross_util_queue.png"), plot(p3, p4; layout = (1, 2), size = (1000, 650)))

# График 4: число исправных машин во времени (один прогон)
one = run_ross(; N = 10, S = 3, nrepair = 1, mttf = 100.0, mttr = 1.0, seed = 1)
p5 = plot(one["t"], one["healthy"]; seriestype = :steppost, legend = false,
          xlabel = "время, часы", ylabel = "число исправных машин")
hline!(p5, [10]; linestyle = :dash)           # ниже этого уровня резерва нет
wsave(plotsdir("ross_healthy.png"), p5)