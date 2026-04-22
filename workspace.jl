using DataFrames, CSV, XLSX

input_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Input"
output_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"

# results = CSV.read(joinpath(output_path, "ToyModelHH_netload_mt.csv"), DataFrame)
# println("Total runs saved: ", ncol(results)-1)

# HHloads = CSV.read(joinpath(input_path, "HHLoadProfile.csv"), DataFrame)
# println("Number of household profiles: ", ncol(HHloads)-1)

facility = CSV.read(joinpath(input_path, "facility.csv"), DataFrame)
# println(unique(facility[!, :meter_place_category]))

house_types = ["Enbostadshus - Tillgänglig", "Enbostadshus - Ej tillgänglig", "Enbostadshus - Produktionsanläggning - Tillgänglig", "Enbostadshus - Produktionsanläggning - Ej tillgänglig"]
apt_types = ["Flerbostadshus - Tillgänglig", "Flerbostadshus - Ej tillgänglig"]

house_facility = filter(row -> coalesce.(row.meter_place_category, "") in house_types, facility)
println("\nNumber of houses: ", nrow(house_facility))
println(combine(groupby(house_facility, :contract_fuse_size), nrow => :num_houses))
apt_facility = filter(row -> coalesce.(row.meter_place_category, "") in apt_types, facility)
println("\nNumber of apartments: ", nrow(apt_facility))
println(combine(groupby(apt_facility, :contract_fuse_size), nrow => :num_apts))

# house_pv_facility = filter(row -> coalesce.(row.conn_power_prod, 0) > 0, house_facility)
# apt_pv_facility = filter(row -> coalesce.(row.conn_power_prod, 0) > 0, apt_facility)

HH_profiles = CSV.read(joinpath(input_path, "HH_sampled_profiles_merged.csv"), DataFrame) 
houses_we_have = filter(row -> row.facility_id in names(HH_profiles), facility)
println(combine(groupby(houses_we_have, :contract_fuse_size), nrow => :num_houses))