using JuMP, HiGHS, PrettyTables, CSV, DataFrames
const AxisArray = Containers.DenseAxisArray

include(joinpath(@__DIR__, "ToyModelHH_loop.jl"))

function runmodel_multithread()
    # Prompt for area selection
    print("Enter area (SE1/SE2/SE3/SE4): ")
    area_str = strip(readline())
    area = Symbol(area_str)
    area ∉ (:SE1, :SE2, :SE3, :SE4) && error("Invalid area: \"$area_str\". Valid options are SE1, SE2, SE3, SE4.")

    (; price, profiles, facility_df) = read_input_data()
    tariff_tables = read_input_tables()

    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    gen_profiles  = collect(Base.axes(profiles.genPVhh, 2))
    gen_pool      = build_genPV_pools(gen_profiles)

    # Build one task per loadHH profile: fuse size → BESS type, random genPV draw
    tasks = Tuple{Symbol, Symbol, Symbol}[]
    for load_p in load_profiles
        facility_row = filter(r -> r.facility_id == String(load_p), facility_df)
        if isempty(facility_row)
            @warn "No facility entry found for load profile $(load_p). Skipping."
            continue
        end
        fuse_size = facility_row[1, :contract_fuse_size]
        if ismissing(fuse_size)
            @warn "Missing fuse size for load profile $(load_p). Skipping."
            continue
        end
        bess_type = fuse_to_bess(fuse_size)
        gen_p     = rand(gen_pool)
        push!(tasks, (Symbol(load_p), Symbol(gen_p), bess_type))
    end
    n_combinations = length(tasks)
    n_threads      = Threads.nthreads()
    n_batches      = ceil(Int, n_combinations / n_threads)
    println("Total combinations: $n_combinations  |  Threads: $n_threads  |  Batches: ~$n_batches")

    output_path  = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"
    # output_file  = joinpath(output_path, "ToyModelHH_results_all_mt.csv")  # not used for now
    netload_file = joinpath(output_path, "ToyModelHH_netload_$(area)_mt.csv")

    # isfile(output_file)  && rm(output_file)   # not used for now
    isfile(netload_file) && rm(netload_file)

    results          = Vector{Union{Nothing, Tuple{String, Vector{Float64}}}}(nothing, n_combinations)
    print_lock       = ReentrantLock()
    stop_flag        = Threads.Atomic{Bool}(false)
    completed_count  = Threads.Atomic{Int}(0)

    try
        Threads.@threads for i in eachindex(tasks)

            stop_flag[] && continue

            load_p, gen_p, bess_type = tasks[i]
            batch_num = ceil(Int, i / n_threads)   # which batch this combination belongs to

            lock(print_lock) do
                println("[batch $batch_num/$n_batches | run $i/$n_combinations | thread $(Threads.threadid())]  Starting: load=$load_p  bess=$bess_type  gen=$gen_p")
            end

            ToyModelHH, params, vars, constraints = makemodel(load_p, gen_p, bess_type, area, price, profiles, tariff_tables)

            (; TIME) = params
            (; NetloadHH, HHcost) = vars

            optimize!(ToyModelHH)

            if termination_status(ToyModelHH) != MOI.OPTIMAL
                lock(print_lock) do
                    @warn "[batch $batch_num/$n_batches | run $i/$n_combinations]  Not optimal for load=$load_p, gen=$gen_p. Skipping."
                end
                results[i] = nothing
                continue
            end

            run_label    = "run_$(i)_load$(load_p)_bess$(bess_type)_gen$(gen_p)"
            netload_vals = [round(value(NetloadHH[t]), digits=4) for t in TIME]
            total_cost   = round(value(HHcost),         digits=4)

            # # Full results: each thread builds its own case_df and appends to file
            # load_vals      = [round(value(loadHH[t]),           digits=4) for t in TIME]
            # gen_vals       = [round(value(genPV[t]),            digits=4) for t in TIME]
            # buy_vals       = [round(value(Buy[t]),              digits=4) for t in TIME]
            # sell_vals      = [round(value(Sell[t]),             digits=4) for t in TIME]
            # charge_vals    = [round(value(ChargeBESS[t]),       digits=4) for t in TIME]
            # discharge_vals = [round(value(DischargeBESS[t]),    digits=4) for t in TIME]
            # soc_vals       = [round(value(SocBESS[t]),          digits=4) for t in TIME]
            # mc_vals        = [round(shadow_price(BalanceHH[t]), digits=4) for t in TIME]
            # case_df = DataFrame(
            #     load_profile   = fill(string(load_p),  length(TIME)),
            #     gen_profile    = fill(string(gen_p),   length(TIME)),
            #     total_cost     = fill(total_cost,       length(TIME)),
            #     time           = collect(TIME),
            #     load           = load_vals,
            #     gen            = gen_vals,
            #     buy            = buy_vals,
            #     sell           = sell_vals,
            #     netload        = netload_vals,
            #     charge_bess    = charge_vals,
            #     discharge_bess = discharge_vals,
            #     soc_bess       = soc_vals,
            #     marginal_cost  = mc_vals,
            # )
            # lock(print_lock) do
            #     CSV.write(output_file, case_df; append=isfile(output_file))
            # end

            results[i] = (run_label, netload_vals)

            Threads.atomic_add!(completed_count, 1)
            pct = round(100 * completed_count[] / n_combinations, digits=1)

            lock(print_lock) do
                println("[batch $batch_num/$n_batches | run $i/$n_combinations | $pct% done]  Finished: load=$load_p  gen=$gen_p  cost=$total_cost")
            end
        end

    catch e
        if e isa InterruptException
            println("\n⚠ Interrupted! Waiting for active solves to finish...")
            stop_flag[] = true
        else
            println("\n⚠ Unexpected error: $e")
            stop_flag[] = true
        end

    finally
        n_saved = count(!isnothing, results)
        println("Completed runs: $n_saved / $n_combinations")

        if n_saved > 0
            println("Writing netload CSV...")

            # Collect completed results in order (preserves run indices from pre-allocated vector)
            solved = [(label, vals) for (label, vals) in skipmissing(
                      [isnothing(r) ? missing : r for r in results])]

            netload_df = DataFrame(time = collect(1:35040))
            for (run_label, netload_vals) in solved
                netload_df[!, Symbol(run_label)] = netload_vals
            end
            CSV.write(netload_file, netload_df)

            println("Netload profiles written to: $netload_file  ($n_saved runs saved)")
        else
            println("No results to save.")
        end
    end
end