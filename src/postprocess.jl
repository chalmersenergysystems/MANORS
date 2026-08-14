using DataFrames, CSV, Statistics

include(joinpath(@__DIR__, "inputdata.jl"))

function load_profiles(region::String)
    # Define paths
    input_path  = raw"C:\Users\corte\Documents\GridHome\Input"
    output_path = raw"C:\Users\corte\Documents\GridHome\Output"
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
    input_path  = raw"C:\Users\corte\Documents\GridHome\Input"
    output_path = raw"C:\Users\corte\Documents\GridHome\Output"

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

function build_netload_profiles()
    path = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"
    runs_path = joinpath(path, "ThereseRuns")

    for area in ["SE1", "SE2", "SE3", "SE4"]
        for tariff in 0:3
            folder = joinpath(runs_path, "Seed18_$(area)_Tariff$(tariff)")
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
            println("Processed optimized netload profiles for $area with tariff $tariff")
        end
        
    end
end

function collect_results(seed::Int, tariff::Int, area::String)
    # Define paths
    path       = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"
    folder     = joinpath(path, "ThereseRuns", "Seed$(seed)_$(area)_Tariff$(tariff)")
    agg_folder = joinpath(path, "ThereseAggs", "Seed$(seed)_Tariff$(tariff)")
    !isdir(agg_folder) && mkpath(agg_folder)

    isdir(folder) || error("Folder not found: $folder")

    # Read all CSV files in the folder
    csv_files = filter(f -> endswith(f, ".csv"), readdir(folder, join=true))
    isempty(csv_files) && error("No CSV files found in $folder")

    # # Initialize DataFrames for aggregation
    # first_df = CSV.read(first(csv_files), DataFrame)
    # df_houseload = DataFrame(time = first_df.time)
    # df_logged    = DataFrame(time = first_df.time)
    # df_driving   = DataFrame(time = first_df.time)
    # df_charge    = DataFrame(time = first_df.time)
    # df_discharge = DataFrame(time = first_df.time)
    # df_public_ch = DataFrame(time = first_df.time)
    # df_baseline  = DataFrame(time = first_df.time)
    # df_optimized = DataFrame(time = first_df.time)
    # df_buy_el    = DataFrame(time = first_df.time)
    # df_sell_el   = DataFrame(time = first_df.time)
    # all_sums     = DataFrame(time = first_df.time)

    # Get baseline timeline information
    first_df = CSV.read(first(csv_files), DataFrame)
    n_rows   = nrow(first_df)
    times    = first_df.time
    
    # Explicit configuration mapping:
    # ( Output File Name, Internal Key / Old DF Name, Source CSV Column )
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

    # for (i, fpath) in enumerate(csv_files)
    #     df = CSV.read(fpath, DataFrame)
    #     cn = Symbol("x$i")

    #     m = Base.match(Regex("with_EV_(.+?)_fuselim_$tariff"), basename(fpath))
    #     ev_id = m !== nothing ? m[1] : "unknown"
    #     push!(ev_mapping, (cn, ev_id))

    #     df_houseload[!, cn] = df.load
    #     df_logged[!, cn]    = df.logged_ev
    #     df_driving[!, cn]   = df.demand_ev
    #     df_charge[!, cn]    = df.charge_ev
    #     df_discharge[!, cn] = df.discharge_ev
    #     df_public_ch[!, cn] = df.public_charge_ev
    #     df_baseline[!, cn]  = df.baseline
    #     df_optimized[!, cn] = df.optimized
    #     df_buy_el[!, cn]    = df.buy
    #     df_sell_el[!, cn]   = df.sell
    # end

    # Loop through and populate files
    for (i, fpath) in enumerate(csv_files)
        df = CSV.read(fpath, DataFrame)
        cn = Symbol("x$i")

        m = Base.match(Regex("with_EV_(.+?)_fuselim_$tariff"), basename(fpath))
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
    println("  Saved aggregates for Seed$(seed)_$(area)")
end

function collect_results()
    path       = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"
    runs_path  = joinpath(path, "ThereseRuns")

    # Discover available seeds from folder names like Seed18_SE1
    subdirs = filter(d -> isdir(joinpath(runs_path, d)), readdir(runs_path))
    seeds   = sort(unique([
        parse(Int, m[1])
        for d in subdirs
        for m in [Base.match(r"^Seed(\d+)_SE\d+_Tariff(\d+)$", d)]
        if m !== nothing
    ]))

    isempty(seeds) && error("No Seed*_SE*_Tariff* folders found in $runs_path")

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
            isdir(joinpath(runs_path, "Seed$(seed)_$(area)_Tariff$(tariff)")) || (@warn "Seed$(seed)_$(area)_Tariff$(tariff) not found, skipping."; continue)
            collect_results(seed, tariff, area)
        end
    end
end

function find_peaks()
    # Define paths
    path = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"
    agg_root = joinpath(path, "ThereseAggs")
    summary = joinpath(agg_root, "Summary")
    isdir(summary) || mkpath(summary)

    day_to_15min = 96                                               # Number of 15-minute intervals in a day (24 hours * 4 intervals per hour)
    month_days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]   # Number of days in each month
    cumulative_15min  = [0; cumsum(month_days)] .* day_to_15min     # Cumulative 15-minute intervals at the end of each month

    for tariff in 0:3
        # Discover seed folders
        seed_folders = filter(
            d -> isdir(joinpath(agg_root, d)) && occursin(Regex("^Seed\\d+_Tariff$(tariff)\$"), d),
            readdir(agg_root)
        )

        summary_peaks_df = DataFrame(seed = Int[], month = String[], area = Symbol[], profile = Symbol[], peak = Float64[])
        summary_dips_df = DataFrame(seed = Int[], month = String[], area = Symbol[], profile = Symbol[], dip = Float64[])

        for seed_folder in seed_folders
            seed = parse(Int, Base.match(r"^Seed(\d+)_Tariff\d+$", seed_folder)[1])
            agg_folder = joinpath(agg_root, seed_folder)

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

function mini_summary_peaks()
    path = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"
    agg_root = joinpath(path, "ThereseAggs")
    summary = joinpath(agg_root, "Summary")

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

        CSV.write(joinpath(summary, "mini_summary_$(var)s.csv"), area_avg)
    end
end

function avg_area(tariff::Int)
    path = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"
    agg_root = joinpath(path, "ThereseAggs")

    # Change based on which results to average
    suffix = "_Tariff$tariff"

    folder = joinpath(agg_root, "Seed18$(suffix)")
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