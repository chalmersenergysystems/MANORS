using JuMP, HiGHS, Gurobi, PrettyTables, CSV, DataFrames, Random
const AxisArray = Containers.DenseAxisArray

include(joinpath(@__DIR__, "GridHome_loop.jl"))

function runmodel_multithread()
    # Prompt for area selection
    print("Enter area (SE1/SE2/SE3/SE4): ")
    area_str = strip(readline())
    area = Symbol(area_str)
    area ∉ (:SE1, :SE2, :SE3, :SE4) && error("Invalid area: \"$area_str\". Valid options are SE1, SE2, SE3, SE4.")

    # Prompt for solver selection
    print("Enter solver (HiGHS vs Gurobi): ")
    solver_str = strip(readline())
    solver = Symbol(solver_str)
    solver ∉ (:HiGHS, :Gurobi) && error("Invalid solver: \"$solver_str\". Valid options are HiGHS, Gurobi.")
    
    println("Running for $area with solver $solver")
    println("------------------------------------------------------------")

    # Read input data
    (; price, profiles, facility_df) = read_input_data()
    tariff_tables = read_input_tables()

    # Read PV profiles for the selected area and add to profiles named tuple
    genPV    = read_PV_data(area)
    profiles = (; profiles..., genPV) 

    # Extract profile names and available regions for user selection
    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    all_gen_profiles = collect(Base.axes(profiles.genPV, 2))

    # Prompt for region selection
    regions_in_area   = gridarea_to_region[String(area)]
    available_regions = [r for r in regions_in_area if any(endswith(String(p), "_$(r)") for p in all_gen_profiles)]
    isempty(available_regions) && error("No PV profiles available for any region in $area.")

    # Prompt for region mode: all or one
    print("Run for all regions or one region? (all/one): ")
    region_mode = strip(readline())
    region_mode ∉ ("all", "one") && error("Invalid choice: \"$region_mode\". Valid options are all, one.")

    if region_mode == "all"
        selected_regions = available_regions
    else
        # Prompt for single region selection
        println("Available regions for $area: $(join(available_regions, ", "))")
        print("Enter region: ")
        region_str = strip(readline())
        region_str ∉ available_regions && error("Invalid region: \"$region_str\". Available: $(join(available_regions, ", "))")
        selected_regions = [region_str]
    end

    println("Selected regions: $(join(selected_regions, ", "))")
    println("------------------------------------------------------------")

    # Build one task per loadHH profile: fuse size → BESS type, random genPV draw
    Random.seed!(RANDOM_SEED)
    tasks = Tuple{Symbol, Symbol, Symbol, String}[]
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
        for region in selected_regions
            region_pool = [p for p in all_gen_profiles if endswith(String(p), "_$(region)")]
            isempty(region_pool) && (@warn "No gen profiles found for region $region. Skipping."; continue)
            gen_p = rand(region_pool)
            push!(tasks, (Symbol(load_p), Symbol(gen_p), bess_type, region))
        end
    end

    n_combinations = length(tasks)
    n_threads      = Threads.nthreads()
    n_batches      = ceil(Int, n_combinations / n_threads)
    println("Total combinations: $n_combinations  |  Threads: $n_threads  |  Batches: ~$n_batches")

    output_path  = raw"C:\Users\corte\Documents\GridHome\Output"
    results          = Vector{Union{Nothing, Tuple{String, Vector{Float64}}}}(nothing, n_combinations)
    print_lock       = ReentrantLock()
    stop_flag        = Threads.Atomic{Bool}(false)
    completed_count  = Threads.Atomic{Int}(0)

    try
        Threads.@threads for i in eachindex(tasks)

            stop_flag[] && continue

            load_p, gen_p, bess_type, region = tasks[i]
            batch_num = ceil(Int, i / n_threads)   # which batch this combination belongs to

            lock(print_lock) do
                println("[batch $batch_num/$n_batches | run $i/$n_combinations | thread $(Threads.threadid())]  Starting: region=$region load=$load_p  bess=$bess_type  gen=$gen_p")
            end

            model, params, vars, constraints = makemodel(load_p, gen_p, bess_type, area, solver, price, profiles, tariff_tables)

            (; TIME) = params
            (; TotCost) = vars

            optimize!(model)
            status = termination_status(model)

            if status != MOI.OPTIMAL
                # Attempt to compute IIS for infeasibility diagnosis
                compute_conflict!(model)

                # If conflict found, save IIS model to file for debugging
                if get_attribute(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
                    iis_model, _ = copy_conflict(model)
                    lock(print_lock) do
                        print(iis_model)
                    end
                end

                # Print warning and skip saving results for this combination
                lock(print_lock) do
                    @warn "[batch $batch_num/$n_batches | run $i/$n_combinations]  Not optimal ($status) for load=$load_p, gen=$gen_p. Skipping."
                end
                results[i] = nothing
                continue
            end

            run_label    = "run_$(i)_load$(load_p)_bess$(bess_type)_gen$(gen_p)"
            netload_vals = [round(value(Netload[t]), digits=4) for t in TIME]
            total_cost   = round(value(TotCost),         digits=4)

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
                println("[batch $batch_num/$n_batches | run $i/$n_combinations | $pct% done]  Finished: region=$region load=$load_p  gen=$gen_p  cost=$total_cost")
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
            println("Writing netload CSVs...")
            for region in selected_regions
                # Collect results in index order (preserves run indices from pre-allocated vector)
                region_indices = [i for i in eachindex(tasks) if tasks[i][4] == region && !isnothing(results[i])]
                if isempty(region_indices)
                    println("No results for region $region, skipping.")
                    continue
                end
                netload_file = joinpath(output_path, "GridHome_netload_$(region).csv")
                netload_df   = DataFrame(time = collect(1:35040))
                for i in region_indices
                    run_label, netload_vals = results[i]
                    netload_df[!, Symbol(run_label)] = netload_vals
                end
                CSV.write(netload_file, netload_df)
                println("Netload profiles written to: $netload_file  ($(length(region_indices)) runs saved)")
            end
        else
            println("No results to save.")
        end
    end
end