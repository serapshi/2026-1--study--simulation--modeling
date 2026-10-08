# # Реализация основных моделей в дискретно-событийном подходе


# ## Инициализация проекта и добавление пакетов
using DrWatson
@quickactivate "project"
include(srcdir("sir_model_const.jl"))
using Random, StatsPlots, BenchmarkTools, CSV

# ## Параметры модели
tmax = 40.0
u0 = [990, 10, 0] # S, I, R
p = [0.05, 10.0, 0.25] # β, c, γ
Random.seed!(1234)

# ## Запуск модели
des_model = MakeSIRModel(u0, p)
activate(des_model)
sir_run(des_model, tmax)
data_des = out(des_model)

@benchmark sir_run(des_model, tmax)
