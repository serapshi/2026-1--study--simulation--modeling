using Distributions, ConcurrentSim, ResumableFunctions, StableRNGs

# Поведение клиента: приходит, ждёт канал, обслуживается, уходит
@resumable function customer(env, server, id, t_a, d_s, rng, log)
    @yield timeout(env, t_a)                 # клиент прибыл
    arrive = now(env)
    @yield request(server)                   # начало обслуживания
    start = now(env)
    @yield timeout(env, rand(rng, d_s))      # канал занят
    @yield unlock(server)                    # клиент ушёл
    push!(log, (id = id, arrival = arrive, start = start, finish = now(env)))
end

# Один прогон модели M/M/c
function run_mmc(; lam, mu, c, num_customers, seed)
    rng = StableRNG(seed)
    arrival_dist = Exponential(1 / lam)
    service_dist = Exponential(1 / mu)
    log = NamedTuple[]
    sim = Simulation()
    server = Resource(sim, c)
    t = 0.0
    for i in 1:num_customers
        t += rand(rng, arrival_dist)
        @process customer(sim, server, i, t, service_dist, rng, log)
    end
    run(sim)
    sort!(log, by = r -> r.id)
    return log
end

# Аналитическое решение M/M/c (формулы из 7.1.2)
function mmc_analytic(lam, mu, c)
    rho = lam / (c * mu)
    rho < 1 || error("Система нестационарна: rho >= 1")
    a = c * rho
    tail = a^c / (factorial(c) * (1 - rho))
    P0 = 1 / (sum(a^n / factorial(n) for n in 0:c-1) + tail)
    Pwait = tail * P0
    Lq = rho / (1 - rho) * Pwait
    Wq = Lq / lam
    W = Wq + 1 / mu
    return (; rho, P0, Pwait, Lq, Wq, W, L = lam * W)
end

# Кусочно-постоянный процесс по моментам событий и приращениям (+1/-1)
function step_series(times, deltas)
    idx = sortperm(times)
    return times[idx], cumsum(deltas[idx])
end

# Число клиентов в очереди и в системе во времени
function queue_series(log)
    n = length(log)
    arr = [r.arrival for r in log]
    sta = [r.start for r in log]
    fin = [r.finish for r in log]
    q = step_series(vcat(arr, sta), vcat(fill(1, n), fill(-1, n)))     # очередь
    s = step_series(vcat(arr, fin), vcat(fill(1, n), fill(-1, n)))     # система
    return q, s
end

# Среднее по времени для кусочно-постоянной функции
function time_avg(t, x)
    T = t[end] - t[1]
    return sum(x[k] * (t[k+1] - t[k]) for k in 1:length(t)-1) / T
end