using Distributions, ConcurrentSim, ResumableFunctions, StableRNGs, LinearAlgebra

# Состояние системы и журнал для мониторинга
mutable struct State
    broken::Int          # число сломанных машин (в очереди + в ремонте)
    waiting::Int         # длина очереди на ремонт
    busy::Int            # число занятых ремонтников
    total::Int           # N + S, всего машин
    t::Vector{Float64}   # моменты изменения состояния
    healthy::Vector{Int} # число исправных машин
    busy_log::Vector{Int}
    queue_log::Vector{Int}
end

State(total) = State(0, 0, 0, total, Float64[], Int[], Int[], Int[])

# Записать текущее состояние в журнал
function record!(st::State, time)
    push!(st.t, time)
    push!(st.healthy, st.total - st.broken)
    push!(st.busy_log, st.busy)
    push!(st.queue_log, st.waiting)
end

# Машина: ждёт активации, работает до отказа, заменяется резервной, чинится
@resumable function machine(env, repair_facility, spares, st, rng, F, G)
    while true
        try
            @yield timeout(env, Inf)          # ждём, пока нас запустят в работу
        catch
        end
        @yield timeout(env, rand(rng, F))     # наработка до отказа
        st.broken += 1                        # машина сломалась
        record!(st, now(env))
        get_spare = take!(spares)             # пытаемся взять резервную машину
        @yield get_spare | timeout(env)
        if state(get_spare) != ConcurrentSim.idle
            @yield interrupt(value(get_spare))  # запускаем резервную в работу
        else
            throw(StopSimulation("No more spares!"))  # резерва нет, система упала
        end
        st.waiting += 1                       # встаём в очередь на ремонт
        record!(st, now(env))
        @yield request(repair_facility)
        st.waiting -= 1                       # ремонт начался
        st.busy += 1
        record!(st, now(env))
        @yield timeout(env, rand(rng, G))     # время ремонта
        @yield unlock(repair_facility)
        st.busy -= 1                          # ремонт закончен
        st.broken -= 1
        record!(st, now(env))
        @yield put!(spares, active_process(env))  # машина идёт в резерв
    end
end

@resumable function start_sim(env, repair_facility, spares, st, rng, F, G, N, S)
    for i in 1:N                              # N рабочих машин
        proc = @process machine(env, repair_facility, spares, st, rng, F, G)
        @yield interrupt(proc)
    end
    for i in 1:S                              # S резервных машин
        proc = @process machine(env, repair_facility, spares, st, rng, F, G)
        @yield put!(spares, proc)
    end
end

# Среднее по времени для кусочно-постоянной функции x(t) на [0, T]
function time_avg(t, x, T)
    s = 0.0
    for k in 1:length(t)-1
        s += x[k] * (t[k+1] - t[k])
    end
    s += x[end] * (T - t[end])
    return s / T
end

# Один прогон до падения системы
function run_ross(; N, S, nrepair, mttf, mttr, seed)
    rng = StableRNG(seed)
    F = Exponential(mttf)                     # наработка до отказа
    G = Exponential(mttr)                     # время ремонта
    sim = Simulation()
    repair_facility = Resource(sim, nrepair)  # nrepair ремонтников
    spares = Store{Process}(sim)
    st = State(N + S)
    record!(st, 0.0)
    @process start_sim(sim, repair_facility, spares, st, rng, F, G, N, S)
    run(sim)
    T = now(sim)                              # момент падения
    return Dict(
        "T" => T,
        "util" => time_avg(st.t, st.busy_log, T) / nrepair,  # загрузка ремонтника
        "Lq" => time_avg(st.t, st.queue_log, T),             # средняя длина очереди
        "t" => st.t,
        "healthy" => st.healthy,
    )
end

# Аналитическое решение: среднее время до поглощения E[T].
# Состояние i = число исправных машин, i = N..N+S; падение при отказе в состоянии N.
function ross_analytic(; N, S, nrepair, mttf, mttr)
    f, m = 1 / mttf, 1 / mttr
    n = S + 1                                 # число невозвратных состояний
    Q = zeros(n, n)
    for k in 1:n
        i = N + k - 1
        fail = N * f                          # суммарная интенсивность отказов
        rep = min(N + S - i, nrepair) * m     # интенсивность ремонта
        Q[k, k] = -(fail + rep)
        k > 1 && (Q[k, k-1] = fail)           # отказ: i -> i-1
        k < n && (Q[k, k+1] = rep)            # ремонт: i -> i+1
    end
    t = -Q \ ones(n)                          # Q * t = -1
    return t[end]                             # старт из состояния N+S
end