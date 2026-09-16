using DataFrames, CSV, Statistics

include(joinpath(@__DIR__, "inputdata.jl"))

# ==============================================================================================
# Terminology used throughout this file (as defined in the README):
#   "individual power tariff" model (GridHome_powertariff.jl), tariff ∈ {0,1,2} (No Tariff /
#     Daytime Tariff / All Hours Tariff). Each household is optimized independently, with its
#     own fuse-based connection limit.
#   "collective power tariff" model (GridHome_collectivetariff.jl), tariff == 3 (Collective
#     Tariff). All households in an area are optimized jointly, sharing one grid connection.
#
# Both models write one CSV per household to the same folder layout:
#   OUTPUT_PATH/Seed<seed>/AllRuns/Seed<seed>_<area>_Tariff<tariff>/
#       GridHome_<area>_<profile>_EV_<ev_id>_Tariff<tariff>.csv
# so the "CURRENT" functions below treat the individual (tariff 0-2) and collective (tariff 3)
# models uniformly — only the tariff number differs.
# ==============================================================================================

# ------------------------------------------------------------------------------------------
# OBSOLETE — these two functions belong to the earlier PV+BESS pipeline (GridHome_loop.jl /
# GridHome_multithread.jl), which optimizes household load against solar generation (genPV)
# and a home battery (BESS); it has no EV and no power tariff, and is unrelated to the
# current individual/collective tariff models. They read/write "GridHome_netload_<region>.csv"
# and "run_<i>_load..._bess..._gen..." named columns that those models never produce.
# Kept only for reference — not updated to the current model/folder structure.
# ------------------------------------------------------------------------------------------
function load_profiles(region::String)
    # Define paths
    input_path  = INPUT_PATH
    output_path = OUTPUT_PATH
    synth_path  = joinpath(input_path, "synth_profiles")

    # Read generation profiles and results from CSV files
    genPV_df   = CSV.read(joinpath(synth_path, "pv_profiles_$(region).csv"), DataFrame)
    results_df = CSV.read(joinpath(output_path, "GridHome_netload_$(region).csv"), DataFrame)

    # Clean up dataframes
    genPV_df   = df_cleanup!(genPV_df)

    return (; genPV_df, results_df)
end

function build_profiles()
    # # Prompt for area selection
    # print("Enter area (SE1/SE2/SE3/SE4): ")
    # area_str = strip(readline())
    # area = Symbol(area_str)
    # area ∉ (:SE1, :SE2, :SE3, :SE4) && error("Invalid area: \"$area_str\". Valid options are SE1, SE2, SE3, SE4.")

    # Define paths
    input_path  = INPUT_PATH
    output_path = OUTPUT_PATH

    # Load shared HH profiles once
    load_df = CSV.read(joinpath(input_path, "HH_sampled_profiles_merged.csv"), DataFrame)
    load_df = df_cleanup!(load_df)

    # Discover regions from netload files
    netload_files = filter(f -> startswith(f, "GridHome_netload_") && endswith(f, ".csv"),
                           readdir(output_path))

    # Define naming pattern
    # uuid_pattern = r"run_\d+_load([a-f0-9\-]+)_bess.+_gen([a-f0-9\-]+)"
    uuid_pattern = r"run_\d+_load([a-f0-9\-]+)_bess.+_gen(x(?:[1-9]\d{0,2}|1000))"

    for file in netload_files
        region = replace(file, "GridHome_netload_" => "", ".csv" => "")
        println("Processing region: $region")

        # Read input data
        (; genPV_df, results_df) = load_profiles(region)

        # Initialize DataFrame to store dummy netloads
        dummy_netloads = DataFrame(time=results_df.time)

        # Iterate over columns in results_df to find original profiles
        for col in names(results_df)
            col == "time" && continue
            m = Base.match(uuid_pattern, col)
            m === nothing && continue

            load_uuid = m[1]
            gen_uuid  = m[2]

            # Find corresponding profiles in load_df and genPV_df
            load_profile  = load_df[:, Symbol(load_uuid)]
            gen_profile   = genPV_df[:, Symbol(gen_uuid)]

            # Calculate dummy netload for comparison
            dummy_netload = load_profile .- gen_profile

            # Store the dummy netload in the new DataFrame
            dummy_col = replace(col, r"_bess[^_]+(?=_gen)" => "")
            dummy_netloads[:, dummy_col] = dummy_netload
        end

        # Save to CSV
        CSV.write(joinpath(output_path, "GridHome_dummyloads_$(region).csv"), dummy_netloads)
    end
end

# ------------------------------------------------------------------------------------------
# CURRENT — postprocessing pipeline for the individual (GridHome_powertariff.jl, tariff 0-2)
# and collective (GridHome_collectivetariff.jl, tariff 3) power tariff models. Run in this order:
#   1. build_netload_profiles(seed)             — adds an `optimized` column to every raw run CSV
#   2. collect_results(seed, tariff, area), or interactively collect_results()
#                                                — aggregates all households in an area into
#                                                  per-metric wide CSVs
#   3. find_peaks()                              — cross-seed monthly peak/dip summary
#   4. compare_tariffs_monthly()                 — compact peak/dip summary across tariffs
#   5. average_areas(seed, tariff)               — averages aggregates across the four areas
# ------------------------------------------------------------------------------------------

function build_netload_profiles(seed::Int)
    # Adds an `optimized` column (net grid draw) to every raw per-household run CSV, so that
    # collect_results can rely on a common column name. Neither the individual nor the
    # collective tariff model defines a `Sell` variable at all right now (both only ever
    # `Buy`), so `optimized` is currently just an alias for `buy`; the `sell` branch is kept
    # temporarily in case a future model variant reintroduces PV/export (V2G, PV, ...) and
    # defines `Sell` again.
    runs_path = joinpath(OUTPUT_PATH, "Seed$(seed)", "AllRuns")

    for area in ["SE1", "SE2", "SE3", "SE4"]
        for tariff in 0:3
            folder = joinpath(runs_path, "Seed$(seed)_$(area)_Tariff$(tariff)")
            isdir(folder) || (@warn "Folder not found: $folder, skipping."; continue)

            csv_files = filter(f -> endswith(f, ".csv"), readdir(folder, join=true))
            isempty(csv_files) && error("No CSV files found in $folder")

            for fpath in csv_files
                df = CSV.read(fpath, DataFrame)

                # Calculate optimized netload
                if hasproperty(df, :optimized)
                    @warn "Column :optimized already exists in $fpath, skipping calculation."
                else
                    df[!, :optimized] = hasproperty(df, :sell) ? (df.buy .- df.sell) : df.buy
                end

                CSV.write(fpath, df)
            end
            println("Processed optimized netload profiles for $area with tariff $tariff (individual if 0-2, collective if 3)")
        end
        
    end
end

function collect_results(seed::Int, tariff::Int, area::String)
    # Aggregates all per-household CSVs for one seed/tariff/area into per-metric wide CSVs
    # (one column per household) plus a one-day percentage breakdown. Works for both the
    # individual tariff model (tariff 0-2) and the collective tariff model (tariff 3), since
    # they share the same per-household file naming.
    folder     = joinpath(OUTPUT_PATH, "Seed$(seed)", "AllRuns", "Seed$(seed)_$(area)_Tariff$(tariff)")
    agg_folder = joinpath(OUTPUT_PATH, "Seed$(seed)", "Aggregates", "Seed$(seed)_Tariff$(tariff)")
    !isdir(agg_folder) && mkpath(agg_folder)

    isdir(folder) || error("Folder not found: $folder")

    # Read all CSV files in the folder
    csv_files = filter(f -> endswith(f, ".csv"), readdir(folder, join=true))
    isempty(csv_files) && error("No CSV files found in $folder")

    # Get baseline timeline information
    first_df = CSV.read(first(csv_files), DataFrame)
    n_rows   = nrow(first_df)
    times    = first_df.time
    
    # Explicit configuration mapping:
    # ( Output File Name, Internal Key / Old DF Name, Source CSV Column )
    # Note: `discharge_ev` and `sell_el` are legacy BESS/V2G columns that the current
    # individual/collective tariff models never produce — they default to zero via
    # `hasproperty` below.
    metrics_config = [
        ("houseload",     :df_houseload, :load),
        ("logged",        :df_logged,    :logged_ev),
        ("driving",       :df_driving,   :demand_ev),
        ("charge",        :df_charge,    :charge_ev),
        ("discharge",     :df_discharge, :discharge_ev),
        ("public_charge", :df_public_ch, :public_charge_ev),
        ("baseline",      :df_baseline,  :baseline),
        ("optimized",     :df_optimized, :optimized),
        ("buy_el",        :df_buy_el,    :buy),
        ("sell_el",       :df_sell_el,   :sell)
    ]

    # Initialize the aggregate dataframes into a dictionary using the old df names as keys
    dfs = Dict(key => DataFrame(time = times) for (_, key, _) in metrics_config)
    
    all_sums = DataFrame(time = times)
    ev_mapping = DataFrame(profile = Symbol[], ev_id = String[])

    # Loop through and populate files
    for (i, fpath) in enumerate(csv_files)
        df = CSV.read(fpath, DataFrame)
        cn = Symbol("x$i")

        # Filename pattern (both individual and collective tariff models): GridHome_<area>_<profile>_EV_<ev_id>_Tariff<tariff>.csv
        m = Base.match(Regex("_EV_(.+?)_Tariff$(tariff)\\.csv\$"), basename(fpath))
        ev_id = m !== nothing ? m[1] : "unknown"
        push!(ev_mapping, (cn, ev_id))

        # Check the source columns and populate the dataframes
        for (_, key, csv_col) in metrics_config
            dfs[key][!, cn] = hasproperty(df, csv_col) ? df[!, csv_col] : zeros(Float64, n_rows)
        end
    end

    CSV.write(joinpath(agg_folder, area * "_ev_mapping.csv"), ev_mapping)

    # Calculate row sums and save individual aggregates using exact names
    for (file_name, key, _) in metrics_config
        out_df = dfs[key]
        out_df[!, :sum] = sum.(eachrow(select(out_df, Not(:time))))
        
        CSV.write(joinpath(agg_folder, area * "_aggregates_" * file_name * ".csv"), out_df)
        all_sums[!, Symbol(file_name)] = out_df.sum
    end

    # Process time buckets
    all_sums[!, :hour] = ceil.(Int, all_sums.time ./ 4)
    sum_cols  = names(all_sums, Not([:time, :hour]))
    hour_sums = combine(groupby(all_sums, :hour), sum_cols .=> sum .=> sum_cols)
    hour_sums[!, :day]         = ceil.(Int, hour_sums.hour ./ 24)
    hour_sums[!, :hour_in_day] = hour_sums.hour .- 24 .* (hour_sums.day .- 1)

    oneday     = combine(groupby(hour_sums, :hour_in_day), sum_cols .=> mean .=> sum_cols)
    oneday_pct = copy(oneday)
    
    # Safe division check against :optimized sum
    opt_sum = sum(oneday[!, :optimized])
    for col in sum_cols
        if opt_sum > 0
            oneday_pct[!, col] = round.(oneday[!, col] ./ opt_sum .* 100, digits=2)
        else
            oneday_pct[!, col] .= 0.0
        end
    end

    CSV.write(joinpath(agg_folder, area * "_oneday_pcts.csv"), oneday_pct)
    println("  Saved aggregates for Seed$(seed)_$(area)_Tariff$(tariff)")
end

function collect_results()
    # Interactive entry point: discovers available seeds directly under OUTPUT_PATH (each
    # seed re-run of the models lives in its own OUTPUT_PATH/Seed<seed>/ folder).
    subdirs = filter(d -> isdir(joinpath(OUTPUT_PATH, d)), readdir(OUTPUT_PATH))
    seeds   = sort(unique([
        parse(Int, m[1])
        for d in subdirs
        for m in [Base.match(r"^Seed(\d+)$", d)]
        if m !== nothing
    ]))

    isempty(seeds) && error("No Seed<N> folders found in $OUTPUT_PATH")

    println("Available seeds: $(join(seeds, ", "))")
    print("Enter seed(s) to process (comma-separated, or 'all'): ")
    input = strip(readline())

    tariff_options = [(0, "No Tariff"), (1, "Daytime Tariff"), (2, "All Hours Tariff"), (3, "Collective Tariff")]
    println("Available tariff options: $(join(["$(opt[1]): $(opt[2])" for opt in tariff_options], ", "))")
    print("Enter tariff option (0-3): ")
    tariff_input = strip(readline())
    tariff = parse(Int, tariff_input)

    chosen_seeds = input == "all" ? seeds : parse.(Int, strip.(split(input, ",")))

    for seed in chosen_seeds
        println("\nProcessing Seed$(seed)...")
        for area in ["SE1", "SE2", "SE3", "SE4"]
            isdir(joinpath(OUTPUT_PATH, "Seed$(seed)", "AllRuns", "Seed$(seed)_$(area)_Tariff$(tariff)")) || (@warn "Seed$(seed)_$(area)_Tariff$(tariff) not found, skipping."; continue)
            collect_results(seed, tariff, area)
        end
    end
end

function find_peaks()
    # Cross-seed summary of monthly peak (max import power) and dip (max export power) per
    # area/household, across every available seed and tariff (0-2 individual, 3 collective).
    # Dips will be ~0 for the current models since neither produces PV export (`sell_el`);
    # kept for compatibility with any future model variant that does export.
    summary = joinpath(OUTPUT_PATH, "Aggregates", "Summary")
    isdir(summary) || mkpath(summary)

    day_to_15min = 96                                               # Number of 15-minute intervals in a day (24 hours * 4 intervals per hour)
    month_days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   # Number of days in each month
    cumulative_15min  = [0; cumsum(month_days)] .* day_to_15min     # Cumulative 15-minute intervals at the end of each month

    # Discover every seed's Aggregates folder directly under OUTPUT_PATH
    seed_dirs = filter(d -> isdir(joinpath(OUTPUT_PATH, d)) && Base.match(r"^Seed(\d+)$", d) !== nothing, readdir(OUTPUT_PATH))

    for tariff in 0:3
        summary_peaks_df = DataFrame(seed = Int[], month = String[], area = Symbol[], profile = Symbol[], peak = Float64[])
        summary_dips_df = DataFrame(seed = Int[], month = String[], area = Symbol[], profile = Symbol[], dip = Float64[])

        for seed_dir in seed_dirs
            seed = parse(Int, Base.match(r"^Seed(\d+)$", seed_dir)[1])
            agg_folder = joinpath(OUTPUT_PATH, seed_dir, "Aggregates", "Seed$(seed)_Tariff$(tariff)")
            isdir(agg_folder) || continue

            for area in [:SE1, :SE2, :SE3, :SE4]
                opt_profiles = CSV.read(joinpath(agg_folder, String(area) * "_aggregates_optimized.csv"), DataFrame)
                sell_profiles = CSV.read(joinpath(agg_folder, String(area) * "_aggregates_sell_el.csv"), DataFrame)
    
                # Define profile columns
                profile_cols = setdiff(names(opt_profiles), ["time"])
                for col in profile_cols
                    opt_profiles[!, col] = abs.(opt_profiles[!, col])
                    sell_profiles[!, col] = abs.(sell_profiles[!, col])
                end

                # Create a DataFrame to store peaks, first column is m1, m2, ..., m12, other columns are the profiles
                peaks_df = DataFrame(month = ["m$m" for m in 1:12])
                dips_df = DataFrame(month = ["m$m" for m in 1:12])

                # Split the optimized profiles into monthly DataFrames
                month_opt_dfs = [opt_profiles[cumulative_15min[m]+1 : cumulative_15min[m+1], :] for m in 1:12]
                month_sell_dfs = [sell_profiles[cumulative_15min[m]+1 : cumulative_15min[m+1], :] for m in 1:12]

                # Find peaks for each month and each profile
                for col in profile_cols
                    peaks_df[!, col] = [maximum(month_df[!, col]) for month_df in month_opt_dfs] .* 4  # Convert from kWh per 15min to kW by multiplying by 4
                    dips_df[!, col] = [maximum(month_df[!, col]) for month_df in month_sell_dfs] .* 4  # Convert from kWh per 15min to kW by multiplying by 4
                end
            
                # Save the peaks DataFrame to CSV
                CSV.write(joinpath(agg_folder, String(area) * "_monthly_peaks.csv"), peaks_df)
                CSV.write(joinpath(agg_folder, String(area) * "_monthly_dips.csv"), dips_df)

                # Add peaks to summary DataFrame
                for col in setdiff(names(peaks_df), ["month"])
                    for i in 1:nrow(peaks_df)
                        push!(summary_peaks_df, (seed, peaks_df.month[i], area, Symbol(col), peaks_df[i, col]))
                    end
                end

                # Add dips to summary DataFrame
                for col in setdiff(names(dips_df), ["month"])
                    for i in 1:nrow(dips_df)
                        push!(summary_dips_df, (seed, dips_df.month[i], area, Symbol(col), dips_df[i, col]))
                    end
                end
            end
        end

        # Save summary DataFrame to CSV
        CSV.write(joinpath(summary, "summary_peaks_Tariff$(tariff).csv"), summary_peaks_df)
        CSV.write(joinpath(summary, "summary_dips_Tariff$(tariff).csv"), summary_dips_df)
    end
end

function compare_tariffs_monthly()
    # Compact peak/dip summary comparing all 4 tariff options: individual No/Daytime/All Hours
    # Tariff (0-2) and collective Collective Tariff (3). Requires find_peaks() to have run first.
    summary = joinpath(OUTPUT_PATH, "Aggregates", "Summary")

    for var in ["peak", "dip"]
        no_tariff = CSV.read(joinpath(summary, "summary_$(var)s_Tariff0.csv"), DataFrame)
        day_time = CSV.read(joinpath(summary, "summary_$(var)s_Tariff1.csv"), DataFrame)
        all_hours = CSV.read(joinpath(summary, "summary_$(var)s_Tariff2.csv"), DataFrame)
        collective = CSV.read(joinpath(summary, "summary_$(var)s_Tariff3.csv"), DataFrame)

        leftjoin!(no_tariff, day_time, on = [:seed, :month, :area, :profile], makeunique=true)
        leftjoin!(no_tariff, all_hours, on = [:seed, :month, :area, :profile], makeunique=true)
        leftjoin!(no_tariff, collective, on = [:seed, :month, :area, :profile], makeunique=true)
        rename!(no_tariff, Dict("$(var)" => "No Tariff", "$(var)_1" => "Daytime Tariff", "$(var)_2" => "All Hours Tariff", "$(var)_3" => "Collective Tariff"))

        sums = filter(row -> row.profile == "sum", no_tariff)
        area_avg = combine(groupby(sums, :month), 
                        "No Tariff" => mean => "No Tariff", 
                        "Daytime Tariff" => mean => "Daytime Tariff", 
                        "All Hours Tariff" => mean => "All Hours Tariff", 
                        "Collective Tariff" => mean => "Collective Tariff"
                        )

        CSV.write(joinpath(summary, "tariff_comparison_monthly_$(var)s.csv"), area_avg)
    end
end

function average_areas(seed::Int, tariff::Int)
    # Averages a seed's per-area aggregates (SE1-SE4) into a single Sweden-wide series, for
    # either an individual tariff (0-2) or the collective Collective Tariff (3).
    agg_root = joinpath(OUTPUT_PATH, "Seed$(seed)", "Aggregates")

    # Change based on which results to average
    suffix = "_Tariff$tariff"

    folder = joinpath(agg_root, "Seed$(seed)$(suffix)")
    summary = joinpath(agg_root, "Summary_temp")
    isdir(summary) || mkpath(summary)

    if tariff == 0
        avg_cols = ["houseload", "logged", "driving", "charge", "discharge", "public_charge", "baseline", "optimized", "buy_el", "sell_el"]
    else
        avg_cols = ["charge", "discharge", "public_charge", "optimized", "buy_el", "sell_el"]
    end

    for col in avg_cols
        SE1 = CSV.read(joinpath(folder, "SE1_aggregates_" * col * ".csv"), DataFrame)
        SE2 = CSV.read(joinpath(folder, "SE2_aggregates_" * col * ".csv"), DataFrame)
        SE3 = CSV.read(joinpath(folder, "SE3_aggregates_" * col * ".csv"), DataFrame)
        SE4 = CSV.read(joinpath(folder, "SE4_aggregates_" * col * ".csv"), DataFrame)

        avg = DataFrame(time = SE1.time)
        avg[!, Symbol(col)] = (SE1[!, :sum] .+ SE2[!, :sum] .+ SE3[!, :sum] .+ SE4[!, :sum]) ./ 4
        CSV.write(joinpath(summary, "area_avg_" * col * suffix * ".csv"), avg)
    end
end