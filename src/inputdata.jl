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
    # Create a mapping from old names to new names
    rename_map = Dict(cols_to_keep .=> Symbol.("profile_", 1:length(cols_to_keep)))
    rename!(df, rename_map)
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

    return (; price, profiles)
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