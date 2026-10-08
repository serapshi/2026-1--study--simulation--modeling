##!/usr/bin/env julia
## add_packages.jl
using Pkg
Pkg.activate(".") # Активируем текущий проект
## ОСНОВНЫЕ ПАКЕТЫ ДЛЯ РАБОТЫ
packages = [
"StableRNGs"
]
println("Установка базовых пакетов...")
Pkg.add(packages)
println("\n✅ Все пакеты установлены!")
println("Для проверки: using DrWatson, DifferentialEquations, Plots")