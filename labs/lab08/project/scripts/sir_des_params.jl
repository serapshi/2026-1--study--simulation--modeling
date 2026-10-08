# # Реализация основных моделей в дискретно-событийном подходе


# ## Инициализация проекта и добавление пакетов
using DrWatson
@quickactivate "project"
include(srcdir("sir_model.jl"))
using Random, StatsPlots, BenchmarkTools, CSV, Dates
script_name = splitext(basename(PROGRAM_FILE))[1]
mkpath(plotsdir(script_name))
mkpath(datadir(script_name))

# ## Параметры модели
tmax = 40.0
u0 = [990, 10, 0] # S, I, R
Random.seed!(1234)

param_dict = Dict(
    :β => [0.03, 0.07], # β - заражение
    :c => [5.0, 15.0], # c - частота контактов
    :γ => [0.15, 0.35], # γ - выздор
    :μ => [0.01, 0.05]
)
param_list = dict_list(param_dict)
# ## Запуск модели

for params in param_list
    @unpack β, c, γ, μ = params
    p = [β, c, γ, μ]
    des_model = MakeSIRModel(u0, p)
    activate(des_model)
    sir_run(des_model, tmax)
    data_des = out(des_model)
    results = @benchmark begin
        m = MakeSIRModel($u0, $p)
        activate(m)
        sir_run(m, $tmax)
    end samples = 3 evals = 1
    println(savename(params), ": ", results)

    @df data_des plot(:t, [:S :I :R], labels = ["S" "I" "R"],
        xlab = "Время", ylab = "Численность",
        title = "SIR (DES), $(savename(params))")
    savefig(plotsdir(script_name, savename("sir_des", params) * ".png"))

    filename = "sir_$(u0[1])_$(u0[2])_$(p[1])_$(p[2])_$(p[3])_$(p[4]).csv"
    CSV.write(datadir("sims", filename), data_des)
end