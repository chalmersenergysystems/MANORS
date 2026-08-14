using DataFrames, CSV, XLSX, AxisArrays, JSON3

# Select electricity price data for the 4 Swedish bidding areas
function prepare_elprice(df, ordered_timestamp)
    område = ["SE1", "SE2", "SE3", "SE4"]
    sweden = filter(row -> row.MapCode in område, df)
    select!(sweden, [Symbol("DateTime(UTC)"), :MapCode, Symbol("Price[Currency/MWh]")])
    sweden = unstack(sweden, :MapCode, Symbol("Price[Currency/MWh]"))
    for col in [:SE1, :SE2, :SE3, :SE4]
        sweden[!, col] = coalesce.(sweden[!, col], 0.0)
    end
    rename!(sweden, Symbol("DateTime(UTC)") => :id_timestamp)

    ordered_timestamp[!, :id_timestamp] = string.(ordered_timestamp.id_timestamp)
    ordered_timestamp[!, :idx] = 1:nrow(ordered_timestamp)
    sweden[!, :id_timestamp] = string.(sweden.id_timestamp)
    sweden[!, :id_timestamp] = sweden.id_timestamp .* "+00:00"
    elprice = semijoin(sweden, ordered_timestamp, on = :id_timestamp)

    # Fix timestep ordering (stitched 2025-2024)
    leftjoin!(elprice, ordered_timestamp, on = :id_timestamp)
    select!(sort!(elprice, :idx), Not(:idx))

    return elprice
end

function filter_ev_data(df::DataFrame, id_col::Symbol, good_ids::Vector{String})
    col = id_col isa Symbol ? id_col : Symbol(id_col)
    if col ∉ propertynames(df)
        valid = filter(id -> Symbol(id) ∈ propertynames(df), good_ids)
        return select(df, :id_timestamp, Symbol.(valid)...)
    else
        return filter(row -> row[col] in good_ids, df)
    end
end

# Clean up dataframes
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

# Convert cleaned dataframes to AxisArrays for easier indexing in the model
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

# Map grid areas to regions for profile selection
gridarea_to_region = Dict(
    "SE1" => ["Norrbotten"],
    "SE2" => ["Västerbotten", "Jämtland", "Västernorrland", "Gävleborg"],
    "SE3" => ["Dalarna", "Värmland", "Örebro", "Västmanland", "Uppsala", "Södermanland", "Stockholm", "VästraGötaland", "Östergötland", "Jönköping", "Gotland"],
    "SE4" => ["Halland", "Kronoberg", "Kalmar", "Skåne", "Blekinge"]
)

# Read input data: electricity prices, load profiles, facility metadata
function read_input_data()
    # Define path
    input_path = raw"C:\Users\corte\Documents\GridHome\Input"

    # Read electricity price data - ENTSOE (2025-2024)
    # entsoe = CSV.read(joinpath(input_path, "ENTSOE day ahead energy prices 2015-2026.csv"), DataFrame)
    # ordered_timestamp = CSV.read(joinpath(input_path, "ordered_timestamp.csv"), DataFrame)
    # elprice_df = prepare_elprice(entsoe, ordered_timestamp)
    # elprice_df = elprice_df[repeat(1:nrow(elprice_df), inner=4), :]

    # Read electricity price data - NordPool (choose between 2021, 2022, 2023, 2024)
    year = 2024
    println("Running with electricity price data from NordPool for $year")
    elprice_df = CSV.read(joinpath(input_path, "supersecret_elprice$year.csv"), DataFrame, delim=";")
    select!(elprice_df, Not(["Delivery Start (CET)", "Delivery End (CET)"]))
    rename!(elprice_df, Symbol("SE1 Price (EUR)") => :SE1, Symbol("SE2 Price (EUR)") => :SE2, Symbol("SE3 Price (EUR)") => :SE3, Symbol("SE4 Price (EUR)") => :SE4)
    elprice_df = elprice_df[repeat(1:nrow(elprice_df), inner=4), :]

    # Read facility metadata
    facility_df = CSV.read(joinpath(input_path, "facility.csv"), DataFrame)

    # Read consumption profiles from CSV files
    loadAPT_df = CSV.read(joinpath(input_path, "APT_sampled_profiles_merged.csv"), DataFrame)
    loadHH_df = CSV.read(joinpath(input_path, "HH_selected_profiles.csv"), DataFrame)
    # println(names(loadHH_df))

    # Clean up dataframes
    loadAPT_df = df_cleanup!(loadAPT_df)
    loadHH_df = df_cleanup!(loadHH_df)

    # Convert to AxisArrays
    loadAPT = df_to_axisarray(loadAPT_df)
    loadHH = df_to_axisarray(loadHH_df)

    # Collect data for return
    price = (; SE1=Array(elprice_df."SE1"), SE2=Array(elprice_df."SE2"), SE3=Array(elprice_df."SE3"), SE4=Array(elprice_df."SE4"))
    profiles = (; loadAPT, loadHH)

    avg_power_tariff = 7.4                    # €/kW/month, based on typical grid tariffs for households in Sweden

    return (; price, profiles, facility_df, avg_power_tariff)
end

# Read PV profiles for the selected gridarea (MULTITHREAD)
function read_PV_data(area::Symbol)
    # Define path
    input_path = raw"C:\Users\corte\Documents\GridHome\Input"
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

    # Clean up and convert to AxisArray
    genPV_df = df_cleanup!(area_df)
    genPV_df = df_to_axisarray(genPV_df)

    return genPV_df
end

# Read PV profiles for the selected region (SINGLE RUN)
function read_PV_data(region::String)
    # Define path
    input_path = raw"C:\Users\corte\Documents\GridHome\Input"
    synth_path = joinpath(input_path, "synth_profiles")

    filepath = joinpath(synth_path, "pv_profiles_$(region).csv")
    isfile(filepath) || error("No PV profile found for region \"$region\".")

    region_df = CSV.read(filepath, DataFrame)

    # Clean up and convert to AxisArray
    genPV_df = df_cleanup!(region_df)
    genPV_df = df_to_axisarray(genPV_df)

    return genPV_df
end

# Read EV input data
function read_EV_data()
    # Define path
    input_path = raw"C:\Users\corte\Documents\GridHome\Input"
    ev_folder = joinpath(input_path, "ev_data")

    # Read EV data
    battery_cap = CSV.read(joinpath(ev_folder, "battery_cap.csv"), DataFrame)
    homeshare = CSV.read(joinpath(ev_folder, "homeshare_ep.csv"), DataFrame)
    tripenergy = CSV.read(joinpath(ev_folder, "tripenergy_ep.csv"), DataFrame)
    chargeenergy = CSV.read(joinpath(ev_folder, "chargeenergy_ep.csv"), DataFrame)

    # Select only good data
    good_ids = JSON3.read(read(joinpath(ev_folder, "EVs_charging_at_home.txt"), String), Vector{String})
    battery_cap = filter_ev_data(battery_cap, :id, good_ids)
    homeshare = filter_ev_data(homeshare, :id, good_ids)
    tripenergy = filter_ev_data(tripenergy, :id, good_ids)
    chargeenergy = filter_ev_data(chargeenergy, :id, good_ids)

    # Fix driving demand data. Note: original data is negative for energy consumed
    for col in names(tripenergy)
        col ∈ ("id_timestamp", "time") && continue
        tripenergy[!, col] = abs.(min.(tripenergy[!, col], 0.0))   # keep negatives, zero out positives, then abs
    end
    # Converted to positive values representing energy consumed

    # Clean up dataframes
    homeshare = df_cleanup!(homeshare)
    tripenergy = df_cleanup!(tripenergy)
    chargeenergy = df_cleanup!(chargeenergy)

    # Convert to AxisArrays
    homeshare = df_to_axisarray(homeshare)
    tripenergy = df_to_axisarray(tripenergy)
    chargeenergy = df_to_axisarray(chargeenergy)

    # EV parameters
    charger_power = 11                      # kW, choose between 3.7 kW (16A, mono-phase), 11 kW (16A, tri-phase) or 22 kW (32A, tri-phase), ref: https://www.evify.se/produkter/laddboxar/
    public_charger_power = 200              # kW, typical max power for public AC chargers
    cost_public_charge = 560.0              # €/MWh, based on average public charging prices in Sweden, ref: https://alternative-fuels-observatory.ec.europa.eu/markets-and-policy/market-and-consumer-insights/electric-vehicle-recharging-prices
    eta_chargeEV = 0.95                     # charging efficiency, for V2G option: discharging efficiency defined in makeparameters() as eta_dischargeEV = eta_chargeEV

    return (; battery_cap, homeshare, tripenergy, chargeenergy, charger_power, public_charger_power, cost_public_charge, eta_chargeEV)
end

readrow(table, rownum, headings) = NamedTuple(h => table[rownum, i+1] for (i, h) in enumerate(headings))    # +1 to ignore the first table column
readtable(table, headings) = Tuple(readrow(table, i, headings) for i = 1:size(table,1))

# Define tariff and battery parameters
function read_input_tables()
    tariffparameters = [
    #                   SE1     SE2     SE3     SE4
    :tariffHH         63.57   58.79   64.72   65.48     # €/MWh
    :tariffAPT        61.54   78.19   76.19  107.88     # €/MWh
    :compensationPV    7.63    7.24    9.80    7.65     # €/MWh
    ]

    batteryparameters = [
    #                      BESS6  BESS10  BESS14  BESS20     
    :sizeBESS                6.0    10.0    14.0    20.0        # kWh
    :rateBESS               0.83    0.75    0.67    0.67        # C-rate
    :eta_chargeBESS         0.95    0.95    0.95    0.95        # charging efficiency
    :eta_dischargeBESS      0.95    0.95    0.95    0.95        # discharging efficiency
    :dodBESS                0.95    0.95    0.95    0.95        # depth of discharge, i.e., usable capacity as % of total capacity
    :costBESS                440     360     330     280        # €/kWh, with Grönt Avdrag (50% subsidy) capped at 100000 SEK (50000 SEK per person)
    :n_cyclesBESS           6000    6000    6000    6000        # number of charge/discharge cycles
    :lifetimeBESS             10      10      10      10        # years
    :sohBESS                 0.6     0.6     0.6     0.6        # state of health at end of life, i.e., remaining capacity as % of original capacity after n_cycles or lifetime, whichever comes first
    ]

    return (; tariffparameters, batteryparameters)
end

# Map fuse size to BESS type and max power
const FUSE_TO_POWER_FACTOR = sqrt(3) * 0.4                                      # conversion factor from fuse size (A) to max power (kW), assuming tri-phase and 400V
const FUSE_TO_POWER = Dict(16 => 11.0, 20 => 14.0, 25 => 17.0, 35 => 24.0)      # approximate max power in kW for each fuse size, ref: https://partilleenergi.se/en/faq/vilket-effektuttag-kan-jag-ha-pa-min-huvudsakring/
const FUSE_TO_BESS = Dict(16 => :BESS6, 20 => :BESS10, 25 => :BESS14, 35 => :BESS20)
const BESS_TO_POWER = Dict(:BESS6 => 11.0, :BESS10 => 14.0, :BESS14 => 17.0, :BESS20 => 24.0)   # max power in kW for the house

# Map fuse size to BESS type. Note: this is a simplified mapping for demonstration purposes. In reality, the appropriate BESS size would depend on the specific load profile, PV generation, and other factors.
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

# Define conversion factor from kWh to MWh for cost calculations
const kWh_to_MWh = 1 / 1000

# Select seed for reproducibility. Note: this is set once at the start of the program, not per profile, to ensure different random draws across profiles while still being reproducible.
const RANDOM_SEED = 18              # Standard = 18

# Define the number of timesteps for each month in a non-leap year (2025)
MONTH_TIMESTEPS = Dict(
    :January   => 1:2976,          # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976
    :February  => 2977:5664,       # 28 days * 24 hours/day * 4 (15-min intervals/hour) = 2688,     2976 + 2688 = 5664
    :March     => 5665:8640,       # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976,     5664 + 2976 = 8640
    :April     => 8641:11520,      # 30 days * 24 hours/day * 4 (15-min intervals/hour) = 2880,     8640 + 2880 = 11520
    :May       => 11521:14496,     # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976,    11520 + 2976 = 14496
    :June      => 14497:17376,     # 30 days * 24 hours/day * 4 (15-min intervals/hour) = 2880,    14496 + 2880 = 17376
    :July      => 17377:20352,     # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976,    17376 + 2976 = 20352
    :August    => 20353:23328,     # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976,    20352 + 2976 = 23328
    :September => 23329:26208,     # 30 days * 24 hours/day * 4 (15-min intervals/hour) = 2880,    23328 + 2880 = 26208
    :October   => 26209:29184,     # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976,    26208 + 2976 = 29184
    :November  => 29185:32064,     # 30 days * 24 hours/day * 4 (15-min intervals/hour) = 2880,    29184 + 2880 = 32064
    :December  => 32065:35040      # 31 days * 24 hours/day * 4 (15-min intervals/hour) = 2976,    32064 + 2976 = 35040
)