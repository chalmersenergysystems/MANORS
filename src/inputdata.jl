using DataFrames, CSV, XLSX, AxisArrays

function prepare_elprice(df, ordered_timestamp)
    område = ["SE1", "SE2", "SE3", "SE4"]
    sweden = filter(row -> row.MapCode in område, df)
    select!(sweden, [Symbol("DateTime(UTC)"), :MapCode, Symbol("Price[Currency/MWh]")])
    sweden = unstack(sweden, :MapCode, Symbol("Price[Currency/MWh]"))
    rename!(sweden, Symbol("DateTime(UTC)") => :id_timestamp)

    ordered_timestamp[!, :id_timestamp] = string.(ordered_timestamp.id_timestamp)
    sweden[!, :id_timestamp] = string.(sweden.id_timestamp)
    sweden[!, :id_timestamp] = sweden.id_timestamp .* "+00:00"
    elprice = semijoin(sweden, ordered_timestamp, on = :id_timestamp)

    return elprice
end

function df_cleanup!(df)
    # Define columns to keep
    if "id_timestamp" in names(df)
        cols_to_keep = names(select(df, Not(:id_timestamp)))
    else
        cols_to_keep = names(df)
    end
    # Replace missing values with zeros
    for col in cols_to_keep
        df[!, col] = coalesce.(df[!, col], 0.0)
    end
    # Create time column and remove "id_timestamp" column
    df.time = 1:nrow(df)
    select!(df, :time, cols_to_keep...)
end

function df_to_axisarray(df)
    row_names = df[!, 1]
    # Remove redundant hour column to avoid sorting issues when we take Matrix(df).
    if "time" in names(df)
        select!(df, Not(:time))
    end

    col_names = Symbol.(names(df)) #|> sort
    select!(df, col_names)

    return AxisArray(Matrix(df), row_names, col_names)
end

gridarea_to_region = Dict(
    "SE1" => ["Norrbotten"],
    "SE2" => ["Västerbotten", "Jämtland", "Västernorrland", "Gävleborg"],
    "SE3" => ["Dalarna", "Värmland", "Örebro", "Västmanland", "Uppsala", "Södermanland", "Stockholm", "VästraGötaland", "Östergötland", "Jönköping", "Gotland"],
    "SE4" => ["Halland", "Kronoberg", "Kalmar", "Skåne", "Blekinge"]
)

function read_input_data()
    # Define path
    input_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Input"

    # Read electricity price data
    entsoe = CSV.read(joinpath(input_path, "ENTSOE day ahead energy prices 2015-2026.csv"), DataFrame)
    ordered_timestamp = CSV.read(joinpath(input_path, "ordered_timestamp.csv"), DataFrame)
    elprice_df = prepare_elprice(entsoe, ordered_timestamp)
    elprice_df = elprice_df[repeat(1:nrow(elprice_df), inner=4), :]

    # Read facility metadata
    facility_df = CSV.read(joinpath(input_path, "facility.csv"), DataFrame)

    # Read consumption profiles from CSV files
    loadAPT_df = CSV.read(joinpath(input_path, "APT_sampled_profiles_merged.csv"), DataFrame)
    loadHH_df = CSV.read(joinpath(input_path, "HH_sampled_profiles_merged.csv"), DataFrame)

    # Clean up dataframes
    loadAPT_df = df_cleanup!(loadAPT_df)
    loadHH_df = df_cleanup!(loadHH_df)

    # Convert to AxisArrays
    loadAPT = df_to_axisarray(loadAPT_df)
    loadHH = df_to_axisarray(loadHH_df)

    # Collect data for return
    price = (; SE1=Array(elprice_df."SE1"), SE2=Array(elprice_df."SE2"), SE3=Array(elprice_df."SE3"), SE4=Array(elprice_df."SE4"))
    profiles = (; loadAPT, loadHH)

    return (; price, profiles, facility_df)
end

function read_PV_data(area::Symbol)
    # Define path
    input_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Input"
    synth_path = joinpath(input_path, "synth_profiles")

    # Read generation profiles from CSV files
    regions = gridarea_to_region[String(area)]
    area_df = nothing
    for region in regions
        filepath = joinpath(synth_path, "pv_profiles_$(region).csv")
        if !isfile(filepath)
            @warn "No PV profile found for region $region, skipping."
            continue
        end
        region_df = CSV.read(filepath, DataFrame)
        # Rename profile columns: original_colname → original_colname_region
        data_cols = [c for c in names(region_df) if c ∉ ("id_timestamp", "time")]
        for col in data_cols
            rename!(region_df, col => "$(col)_$(region)")
        end
        if isnothing(area_df)
            area_df = region_df
        else
            area_df = hcat(area_df, region_df[!, ["$(col)_$(region)" for col in data_cols]])
        end
    end
    isnothing(area_df) && error("No PV profiles found for any region in $area.")

    # Clean up dataframe
    genPV_df = df_cleanup!(area_df)

    # Convert to AxisArrays
    genPV_df = df_to_axisarray(genPV_df)

    return genPV_df
end

readrow(table, rownum, headings) = NamedTuple(h => table[rownum, i+1] for (i, h) in enumerate(headings))    # +1 to ignore the first table column
readtable(table, headings) = Tuple(readrow(table, i, headings) for i = 1:size(table,1))

function read_input_tables()
    tariffparameters = [
    #                   SE1     SE2     SE3     SE4
    :tariffHH         63.57   58.79   64.72   65.48     # €/MWh
    :tariffAPT        61.54   78.19   76.19  107.88     # €/MWh
    :compensationPV    7.63    7.24    9.80    7.65     # €/MWh
    ]

    batteryparameters = [
    #                      BESS6  BESS10  BESS13  BESS20
    :sizeBESS                6.6    10.0    13.3    20.0     # kWh
    :rateBESS                1.0     1.0     0.5     1.0     # C-rate
    :eta_chargeBESS         0.95    0.95    0.95    0.95     # charging efficiency
    :eta_dischargeBESS      0.95    0.95    0.95    0.95     # charging efficiency
    # :lossesBESS             0.01    0.01    0.01    0.01     # self-discharge loss per year
    ]

    return (; tariffparameters, batteryparameters)
end

const FUSE_TO_BESS = Dict(16 => :BESS6, 20 => :BESS10, 25 => :BESS13, 35 => :BESS20)

# const FUSE_TO_POWER = Dict(16 => 11.0, 20 => 14.0, 25 => 17.0, 35 => 24.0)   # approximate max power in kW for each fuse size, https://partilleenergi.se/en/faq/vilket-effektuttag-kan-jag-ha-pa-min-huvudsakring/
const BESS_TO_POWER = Dict(:BESS6 => 11.0, :BESS10 => 14.0, :BESS13 => 17.0, :BESS20 => 24.0)   # max power in kW for the house

function fuse_to_bess(fuse_size)
    bess = get(FUSE_TO_BESS, Int(fuse_size), nothing)
    if isnothing(bess)
        error("No BESS mapping defined for fuse size $(fuse_size)A. Known sizes: $(sort(collect(keys(FUSE_TO_BESS))))A")
    end
    return bess
end

# function fuse_to_power(fuse_size)
#     maxpower = get(FUSE_TO_POWER, Int(fuse_size), nothing)
#     if isnothing(maxpower)
#         error("No power mapping defined for fuse size $(fuse_size)A. Known sizes: $(sort(collect(keys(FUSE_TO_POWER))))A")
#     end
#     return maxpower
# end

# Placeholder: returns all genPV profile IDs as a single flat pool.
# Replace this function to partition profiles by fuse size or PV peak power.
function build_genPV_pools(genPV_profiles)
    return genPV_profiles
end

# Select seed for reproducibility. Note: this is set once at the start of the program, not per profile, to ensure different random draws across profiles while still being reproducible.
const RANDOM_SEED = 18