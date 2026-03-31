using JuMP, HiGHS, PrettyTables, CSV, DataFrames
const AxisArray = Containers.DenseAxisArray

include("inputdata.jl")
include("ToyModelHH_loop.jl")

function runmodel_multithread()
    (; profiles) = read_input_data()

    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    gen_profiles  = collect(Base.axes(profiles.genPVhh, 2))

    combinations   = [(load_p, gen_p) for load_p in load_profiles for gen_p in gen_profiles]
    n_combinations = length(combinations)
    n_threads      = Threads.nthreads()
    n_batches      = ceil(Int, n_combinations / n_threads)
    println("Total combinations: $n_combinations  |  Threads: $n_threads  |  Batches: ~$n_batches")

    output_path  = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"
    # output_file  = joinpath(output_path, "ToyModelHH_results_all_mt.csv")  # not used for now
    netload_file = joinpath(output_path, "ToyModelHH_netload_mt.csv")

    # isfile(output_file)  && rm(output_file)   # not used for now
    isfile(netload_file) && rm(netload_file)

    results          = Vector{Union{Nothing, Tuple{String, Vector{Float64}}}}(nothing, n_combinations)
    print_lock       = ReentrantLock()
    stop_flag        = Threads.Atomic{Bool}(false)
    completed_count  = Threads.Atomic{Int}(0)

    try
        Threads.@threads for i in eachindex(combinations)

            stop_flag[] && continue

            load_p, gen_p = combinations[i]
            batch_num     = ceil(Int, i / n_threads)   # which batch this combination belongs to

            lock(print_lock) do
                println("[batch $batch_num/$n_batches | run $i/$n_combinations | thread $(Threads.threadid())]  Starting: load=$load_p  gen=$gen_p")
            end

            ToyModelHH, params, vars, constraints = makemodel(Symbol(load_p), Symbol(gen_p))

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

            run_label    = "run_$(i)_load$(load_p)_gen$(gen_p)"
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
            println("Writing netload CSV incrementally...")

            # Collect only the solved results in order
            solved = [(label, vals) for (label, vals) in skipmissing(
                      [isnothing(r) ? missing : r for r in results])]

            # Build and write in chunks of 100 columns to limit memory usage
            chunk_size = 100
            first_chunk = true
            TIME = 1:35040

            for chunk_start in 1:chunk_size:length(solved)
                chunk_end = min(chunk_start + chunk_size - 1, length(solved))
                chunk     = solved[chunk_start:chunk_end]

                chunk_df = DataFrame(time = collect(TIME))
                for (run_label, netload_vals) in chunk
                    chunk_df[!, Symbol(run_label)] = netload_vals
                end

                if first_chunk
                    CSV.write(netload_file, chunk_df)
                    first_chunk = false
                else
                    # Append columns: re-read existing file and merge
                    existing_df = CSV.read(netload_file, DataFrame)
                    merged_df   = hcat(existing_df, chunk_df[:, 2:end])
                    CSV.write(netload_file, merged_df)
                end

                println("  Written columns $(chunk_start) to $(chunk_end) / $(length(solved))")

                # Free chunk memory immediately
                chunk_df = nothing
                GC.gc()
            end

            println("Netload profiles written to: $netload_file  ($n_saved runs saved)")
        else
            println("No results to save.")
        end
    end
end