# # Реализация основных моделей в дискретно-событийном подходе


# ## Сравнение длительности болезни
using DrWatson
using DataFrames, StatsPlots, CSV

a = CSV.read(datadir("des_exp.csv"), DataFrame)
b = CSV.read(datadir("des_const.csv"), DataFrame)
plot(a.t, a.I, label = "I, экспоненциальная")
plot!(b.t, b.I, label = "I, фиксированная 1/γ")
savefig(plotsdir("exp_vs_const.png"))
