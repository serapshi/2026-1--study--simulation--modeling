using ResumableFunctions, ConcurrentSim, Distributions, DataFrames, Random

# Вспомогательные функции для обновления массивов состояния
function increment!(a::Array{Int64})
    push!(a, a[length(a)] + 1)
end

function decrement!(a::Array{Int64})
    push!(a, a[length(a)] - 1)
end

function carryover!(a::Array{Int64})
    push!(a, a[length(a)])
end

# Структуры данных
mutable struct SIRPerson
    id::Int64
    status::Symbol # :S, :I, :R
end

mutable struct SIRModel
    sim::ConcurrentSim.Simulation # Тип Simulation, не Environment
    β::Float64
    c::Float64
    γ::Float64
    μ::Float64
    ta::Array{Float64}
    Sa::Array{Int64}
    Ia::Array{Int64}
    Ra::Array{Int64}
    allIndividuals::Array{SIRPerson}
end

# Функции обновления статистики при событиях
function infection_update!(sim::ConcurrentSim.Simulation, m::SIRModel)
    push!(m.ta, ConcurrentSim.now(sim))
    decrement!(m.Sa)
    increment!(m.Ia)
    carryover!(m.Ra)
end

function recovery_update!(sim::ConcurrentSim.Simulation, m::SIRModel)
    push!(m.ta, ConcurrentSim.now(sim))
    carryover!(m.Sa)
    decrement!(m.Ia)
    increment!(m.Ra)
end

function birth_update!(sim::ConcurrentSim.Simulation, m::SIRModel)
    push!(m.ta, ConcurrentSim.now(sim))
    increment!(m.Sa)
    carryover!(m.Ia)
    carryover!(m.Ra)
end

function death_update!(sim::ConcurrentSim.Simulation, m::SIRModel, old::Symbol)
    push!(m.ta, ConcurrentSim.now(sim))
    old == :S ? decrement!(m.Sa) : carryover!(m.Sa)
    old == :I ? decrement!(m.Ia) : carryover!(m.Ia)
    old == :R ? decrement!(m.Ra) : carryover!(m.Ra)
end

# Основная логика жизни индивида
@resumable function live(env::ConcurrentSim.Simulation, individual::SIRPerson, m::SIRModel)
    t_death = m.μ > 0 ? ConcurrentSim.now(env) + rand(Exponential(1 / m.μ)) : Inf

    while individual.status == :S
        wait = rand(Exponential(1 / m.c))
        # Смерть наступает раньше следующего контакта
        if ConcurrentSim.now(env) + wait >= t_death
            @yield timeout(env, t_death - ConcurrentSim.now(env))
            death_update!(env, m, :S)
            individual.status = :D
            return
        end
        @yield timeout(env, wait)
        alter = individual
        while alter == individual || alter.status == :D
            N = length(m.allIndividuals)
            index = rand(DiscreteUniform(1, N))
            alter = m.allIndividuals[index]
        end
        if alter.status == :I
            if rand(Uniform(0, 1)) < m.β
                individual.status = :I
                infection_update!(env, m)
            end
        end
    end
    if individual.status == :I
        wait = rand(Exponential(1 / m.γ))
        # Смерть наступает раньше выздоровления
        if ConcurrentSim.now(env) + wait >= t_death
            @yield timeout(env, t_death - ConcurrentSim.now(env))
            death_update!(env, m, :I)
            individual.status = :D
            return
        end
        @yield timeout(env, wait)
        individual.status = :R
        recovery_update!(env, m)
    end
    if individual.status == :R && t_death < Inf
        @yield timeout(env, t_death - ConcurrentSim.now(env))
        death_update!(env, m, :R)
        individual.status = :D
    end
end

@resumable function birth(env::ConcurrentSim.Simulation, m::SIRModel, Λ::Float64)
    while true
        @yield timeout(env, rand(Exponential(1 / Λ)))
        newborn = SIRPerson(length(m.allIndividuals) + 1, :S)
        push!(m.allIndividuals, newborn)
        birth_update!(env, m)
        @process live(env, newborn, m)
    end
end

@resumable function vaccinate(env::ConcurrentSim.Simulation, m::SIRModel,time::Float64, fraction::Float64)
    @yield timeout(env, time)
    susc = [x for x in m.allIndividuals if x.status == :S]
    n_vacc = round(Int, fraction * length(susc))
    for x in first(shuffle(susc), n_vacc)
        x.status = :R
        push!(m.ta, ConcurrentSim.now(env))
        decrement!(m.Sa); carryover!(m.Ia); increment!(m.Ra)
    end
end



# Функции создания и запуска модели
function MakeSIRModel(u0, p)
    (S, I, R) = u0
    N = S + I + R
    (β, c, γ, μ) = p
    
    sim = ConcurrentSim.Simulation() # Создаём именно Simulation
    allIndividuals = SIRPerson[]
    for i = 1:S
        push!(allIndividuals, SIRPerson(i, :S))
    end
    for i = (S+1):(S+I)
        push!(allIndividuals, SIRPerson(i, :I))
    end
    for i = (S+I+1):N
        push!(allIndividuals, SIRPerson(i, :R))
    end
    ta = Float64[0.0]
    Sa = Int64[S]
    Ia = Int64[I]
    Ra = Int64[R]
    SIRModel(sim, β, c, γ, μ, ta, Sa, Ia, Ra, allIndividuals)
end

function activate(m::SIRModel)
    for ind in m.allIndividuals
        @process live(m.sim, ind, m)
    end
    m.μ > 0 && @process birth(m.sim, m, m.μ * length(m.allIndividuals))
end

function sir_run(m::SIRModel, tf::Float64)
    ConcurrentSim.run(m.sim, tf)
end

function out(m::SIRModel)
    result = DataFrame()
    result[!, :t] = m.ta
    result[!, :S] = m.Sa
    result[!, :I] = m.Ia
    result[!, :R] = m.Ra
    return result
end