using DataFrames, CSV

include(joinpath(@__DIR__, "inputdata.jl"))

function load_profiles(area::Symbol)
    # Define paths
    input_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Input"
    output_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"
    synth_path = (joinpath(input_path, "synth_profiles"))

    # Read input data
    load_df = CSV.read(joinpath(input_path, "HH_sampled_profiles_merged.csv"), DataFrame)
    if area == :SE1
        genPV_df = CSV.read(joinpath(synth_path, "pv_profiles_Norrbotten.csv"), DataFrame)
    elseif area == :SE2
        genPV_df = CSV.read(joinpath(synth_path, "pv_profiles_Jämtland.csv"), DataFrame)
    elseif area == :SE3
        genPV_df = CSV.read(joinpath(synth_path, "pv_profiles_Stockholm.csv"), DataFrame)
    elseif area == :SE4
        genPV_df = CSV.read(joinpath(synth_path, "pv_profiles_Skåne.csv"), DataFrame)
    end

    # Clean up dataframes
    load_df = df_cleanup!(load_df)
    genPV_df = df_cleanup!(genPV_df)

    # Read results data
    results_df = CSV.read(joinpath(output_path, "ToyModelHH_netload_$(area)_synth.csv"), DataFrame)

    return (; load_df, genPV_df, results_df)
end

function build_profiles()
    # Prompt for area selection
    print("Enter area (SE1/SE2/SE3/SE4): ")
    area_str = strip(readline())
    area = Symbol(area_str)
    area ∉ (:SE1, :SE2, :SE3, :SE4) && error("Invalid area: \"$area_str\". Valid options are SE1, SE2, SE3, SE4.")

    # Read input data
    (; load_df, genPV_df, results_df) = load_profiles(area)

    # Define naming pattern
    # uuid_pattern = r"run_\d+_load([a-f0-9\-]+)_bess.+_gen([a-f0-9\-]+)"
    uuid_pattern = r"run_\d+_load([a-f0-9\-]+)_bess.+_gen(x(?:[1-9]\d{0,2}|1000))"

    # Initialize DataFrame to store dummy netloads
    dummy_netloads = DataFrame(time=results_df.time)

    # Iterate over columns in results_df to find original profiles
    for col in names(results_df)
        if col == "time"
            continue
        end
        m = match(uuid_pattern, col)
        if m !== nothing
            load_uuid = m[1]
            gen_uuid  = m[2]
            println("Col: $col → load: $load_uuid | gen: $gen_uuid")
        end 

        # Find corresponding profiles in load_df and genPV_df
        load_profile = load_df[:, Symbol(load_uuid)]
        gen_profile = genPV_df[:, Symbol(gen_uuid)]

        # Calculate dummy netload for comparison
        dummy_netload = load_profile - gen_profile

        # Store the dummy netload in the new DataFrame
        dummy_col = replace(col, r"_bess[^_]+(?=_gen)" => "")
        dummy_netloads[:, dummy_col] = dummy_netload
    end

    # Save to CSV
    output_path  = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"
    CSV.write(joinpath(output_path, "ToyModelHH_dummyloads_$(area)_synth.csv"), dummy_netloads)

    return dummy_netloads
end