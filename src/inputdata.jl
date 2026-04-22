using DataFrames, CSV, XLSX, AxisArrays

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

function read_input_data()
    # Define path
    input_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Input"

    # Read electricity price data
    elprice_df = DataFrame(XLSX.readtable(joinpath(input_path, "Electricity_Cost_Sweden_SE3.xlsx"), "new_price_profiles2025"))
    elprice_df = elprice_df[repeat(1:nrow(elprice_df), inner=4), :]
    elprice_df.time = 1:nrow(elprice_df)

    # Read facility metadata
    facility_df = CSV.read(joinpath(input_path, "facility.csv"), DataFrame)

    # Read input data from CSV files
    loadAPT_df = CSV.read(joinpath(input_path, "APT_sampled_profiles_merged.csv"), DataFrame)
    loadHH_df = CSV.read(joinpath(input_path, "HH_sampled_profiles_merged.csv"), DataFrame)
    genPV_df = CSV.read(joinpath(input_path, "pv_profiles_filtered.csv"), DataFrame)
    genPVapt_df = CSV.read(joinpath(input_path, "pv_profiles_filtered_apt.csv"), DataFrame)
    genPVhh_df = CSV.read(joinpath(input_path, "pv_profiles_filtered_best.csv"), DataFrame)

    # Clean up dataframes
    loadAPT_df = df_cleanup!(loadAPT_df)
    loadHH_df = df_cleanup!(loadHH_df)
    genPV_df = df_cleanup!(genPV_df)
    genPVapt_df = df_cleanup!(genPVapt_df)
    genPVhh_df = df_cleanup!(genPVhh_df)
    
    # Convert to AxisArrays
    loadAPT = df_to_axisarray(loadAPT_df)
    loadHH = df_to_axisarray(loadHH_df)
    genPV = df_to_axisarray(genPV_df)
    genPVapt = df_to_axisarray(genPVapt_df)
    genPVhh = df_to_axisarray(genPVhh_df)

    # Collect data for return
    price = (; present=Array(elprice_df."2030"), future=Array(elprice_df."2050"))
    profiles = (; loadAPT, loadHH, genPVapt, genPVhh)

    return (; price, profiles, facility_df)
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

function fuse_to_bess(fuse_size)
    bess = get(FUSE_TO_BESS, Int(fuse_size), nothing)
    if isnothing(bess)
        error("No BESS mapping defined for fuse size $(fuse_size)A. Known sizes: $(sort(collect(keys(FUSE_TO_BESS))))A")
    end
    return bess
end

# Placeholder: returns all genPVhh profile IDs as a single flat pool.
# Replace this function to partition profiles by fuse size or PV peak power.
function build_genPV_pools(genPVhh_profiles)
    return genPVhh_profiles
end