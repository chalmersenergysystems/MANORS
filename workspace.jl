using DataFrames, CSV, XLSX

input_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Input"
output_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"

# results = CSV.read(joinpath(output_path, "ToyModelHH_netload_mt.csv"), DataFrame)
# println("Total runs saved: ", ncol(results)-1)

HHloads = CSV.read(joinpath(input_path, "HHLoadProfile.csv"), DataFrame)
println("Number of household profiles: ", ncol(HHloads)-1)

facility = CSV.read(joinpath(input_path, "facility.csv"), DataFrame)