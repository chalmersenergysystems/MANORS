using JuMP, HiGHS, Gurobi, PrettyTables, Random
const AxisArray = Containers.DenseAxisArray
const GRB_ENV = Gurobi.Env(output_flag = 0)

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

include(joinpath(@__DIR__, "inputdata.jl"))

# Standalone variant: reads all input data internally.
# Use for single interactive model runs (e.g. called directly from makemodel/runmodel).
function makeparameters(load_profile, gen_profile, bess_type, area::Symbol)
    (; price, profiles) = read_input_data()
    genPV_data = read_PV_data(area)
    (; tariffparameters, batteryparameters) = read_input_tables()

    # --- Model sets ---
    TIME = 1:35040
    AREA = [:SE1, :SE2, :SE3, :SE4]
    BESS = [:BESS6, :BESS10, :BESS13, :BESS20]

    # --- Model parameters ---
    elprice = getproperty(price, area)[TIME]                            # €/MWh, 15-min resolution
    loadHH = profiles.loadHH[TIME, load_profile]                        # kWh/15-min
    genPV = genPV_data[TIME, gen_profile]                               # kWh/15-min

    tariffHH, _, compensationPV = readtable(tariffparameters, AREA)

    sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS = readtable(batteryparameters, BESS)

    # Household parameters
    # maxpower = FUSE_TO_POWER[fuse_size]             # kW, add 20 kW to ensure no infeasibility due to the fuse limit (since we want to analyze the effect of the EV without fuse limitations)
    maxpower = fuse_size * FUSE_TO_POWER_FACTOR     # kW, current (A) * tri-phase * voltage (kV)
    overload_tol = 0.10                             # overload tolerance

    return (; TIME, AREA, area, bess_type, maxpower, overload_tol, loadHH, genPV, tariffHH, compensationPV, elprice, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS)
end

# Batch variant: receives pre-loaded data (price, profiles with genPV, tariff_tables).
# Use for multithreaded/loop runs where data is loaded once outside the loop.
function makeparameters(load_profile, gen_profile, bess_type, area::Symbol, price, profiles, tariff_tables)
    (; tariffparameters, batteryparameters) = tariff_tables

    # --- Model sets ---
    TIME = 1:35040
    AREA = [:SE1, :SE2, :SE3, :SE4]
    BESS = [:BESS6, :BESS10, :BESS13, :BESS20]

    # --- Model parameters ---
    elprice = getproperty(price, area)[TIME]                            # €/MWh, 15-min resolution
    loadHH = profiles.loadHH[TIME, load_profile]                        # kWh/15-min
    genPV = profiles.genPV[TIME, gen_profile]                               # kWh/15-min

    tariffHH, _, compensationPV = readtable(tariffparameters, AREA)
    sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS = readtable(batteryparameters, BESS)

    # Household parameters
    # maxpower = FUSE_TO_POWER[fuse_size]             # kW, add 20 kW to ensure no infeasibility due to the fuse limit (since we want to analyze the effect of the EV without fuse limitations)
    maxpower = fuse_size * FUSE_TO_POWER_FACTOR     # kW, current (A) * tri-phase * voltage (kV)
    overload_tol = 0.10                             # overload tolerance

    return (; TIME, AREA, area, bess_type, maxpower, overload_tol, loadHH, genPV, tariffHH, compensationPV, elprice, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS)
end

function makevariables(model, params)
    (; TIME, bess_type) = params

    @variables model begin
        TotCost                                                                     # €/year
        0 <= Buy[t in TIME]            <= maxpower / 4 * (1 + overload_tol)         # kWh/15-min
        0 <= Sell[t in TIME]           <= maxpower / 4 * (1 + overload_tol)         # kWh/15-min
        0 <= ChargeBESS[t in TIME]                                                  # kW
        0 <= DischargeBESS[t in TIME]                                               # kW
        0 <= SocBESS[t in TIME]        <= sizeBESS[bess_type]                       # kWh
    end

    return (; TotCost, Buy, Sell, ChargeBESS, DischargeBESS, SocBESS)
end

function makeconstraints(model, vars, params)
    (; TIME, area, bess_type, maxpower, loadHH, genPV, tariffHH, compensationPV, elprice, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS) = params
    (; TotCost, Buy, Sell, ChargeBESS, DischargeBESS, SocBESS) = vars
    
    @constraints model begin
        BalanceHH[t in TIME],
            genPV[t] + DischargeBESS[t] + Buy[t] == loadHH[t] + ChargeBESS[t] + Sell[t]                 # alternatively do >=

        BalanceBESS[t in TIME],
            SocBESS[t == TIME[end] ? TIME[1] : t+1] <= SocBESS[t] + (ChargeBESS[t] * eta_chargeBESS[bess_type]) - (DischargeBESS[t] / eta_dischargeBESS[bess_type])

        LimitChargeBESS[t in TIME],
            ChargeBESS[t] <= sizeBESS[bess_type] * rateBESS[bess_type] / 4      # kWh/15-min
        
        LimitDischargeBESS[t in TIME],
            DischargeBESS[t] <= sizeBESS[bess_type] * rateBESS[bess_type] / 4   # kWh/15-min

        Totalcosts,
            TotCost == sum(Buy[t] * (elprice[t] + tariffHH[area]) for t in TIME) - sum(Sell[t] * (elprice[t] + compensationPV[area]) for t in TIME)
    end

    return (; BalanceHH, BalanceBESS, 
              LimitChargeBESS, LimitDischargeBESS, 
              Totalcosts)
end

function set_solver(solver::Symbol)
    if solver == :HiGHS
        return optimizer_with_attributes(
            HiGHS.Optimizer,
            "presolve"       => "on",
            "solver"         => "ipx",
            "run_crossover"  => "on",
            "ranging"        => "on",
        )
    elseif solver == :Gurobi
        return optimizer_with_attributes(
            () -> Gurobi.Optimizer(GRB_ENV),
            "OutputFlag"     => 0,
            "BarHomogeneous" => 1,
            "Crossover"      => 1,
            "Method"         => 2,
            "DualReductions" => 0,
        )
    else
        error("Unknown solver: $solver. Valid options are :HiGHS, :Gurobi.")
    end
end

# Standalone variant: reads all input data internally via the standalone makeparameters.
# Use for single interactive runs.
function makemodel(load_profile, gen_profile, bess_type, area::Symbol, solver::Symbol)
    optimizer = set_solver(solver)
    model = Model(optimizer)

    params = makeparameters(load_profile, gen_profile, bess_type, area)
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; TotCost) = vars

    @objective model Min begin
        TotCost
    end

    return model, params, vars, constraints
end

# Batch variant: receives pre-loaded data and passes it to the batch makeparameters.
# Use for multithreaded/loop runs (runmodel, runmodel_multithread).
function makemodel(load_profile, gen_profile, bess_type, area::Symbol, solver::Symbol, price, profiles, tariff_tables)
    optimizer = set_solver(solver)
    model = Model(optimizer)
    set_silent(model)

    params      = makeparameters(load_profile, gen_profile, bess_type, area, price, profiles, tariff_tables)
    vars        = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; TotCost) = vars

    @objective model Min begin
        TotCost
    end

    return model, params, vars, constraints
end

function runmodel()
    # Prompt for area selection
    print("Enter area (SE1/SE2/SE3/SE4): ")
    area_str = strip(readline())
    area = Symbol(area_str)
    area ∉ (:SE1, :SE2, :SE3, :SE4) && error("Invalid area: \"$area_str\". Valid options are SE1, SE2, SE3, SE4.")

    # Prompt for solver selection
    print("Enter solver (HiGHS vs Gurobi): ")
    solver_str = strip(readline())
    solver = Symbol(solver_str)
    solver ∉ (:HiGHS, :Gurobi) && error("Invalid solver: \"$solver_str\". Valid options are HiGHS, Gurobi.")

    println("Running for $area with solver $solver")

    (; price, profiles, facility_df) = read_input_data()
    tariff_tables = read_input_tables()
    genPV    = read_PV_data(area)                                # ← add
    profiles = (; profiles..., genPV) 

    # Extract profile names and available regions for user selection
    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    all_gen_profiles = collect(Base.axes(profiles.genPV, 2))

    output_path  = OUTPUT_PATH
    # output_file  = joinpath(output_path, "MANORS_results_all.csv")  # not used for now
    netload_file = joinpath(output_path, "MANORS_netload_$(area).csv")

    # isfile(output_file)  && rm(output_file)   # not used for now
    isfile(netload_file) && rm(netload_file)

    # first_write = true   # not used for now
    run_counter = 0

    # Initialise the netload DataFrame on the first run
    netload_df = nothing

    Random.seed!(RANDOM_SEED)
    for load_p in load_profiles
        # Look up fuse size and derive BESS type
        facility_row = filter(r -> r.facility_id == String(load_p), facility_df)
        if isempty(facility_row)
            @warn "No facility entry found for load profile $(load_p). Skipping."
            continue
        end
        fuse_size = facility_row[1, :contract_fuse_size]
        bess_type = fuse_to_bess(fuse_size)

        # Draw one genPV profile at random from all regions in the area.
        # Note: unlike runmodel_multithread, runmodel has no region prompt and draws
        # from the full area pool. Add a region prompt here if region-level separation is needed.
        gen_p = rand(all_gen_profiles)

        println("Running: load=$(load_p)  |  fuse=$(fuse_size)A  |  bess=$(bess_type)  |  gen=$(gen_p)")

        model, params, vars, constraints = makemodel(Symbol(load_p), Symbol(gen_p), bess_type, area, solver, price, profiles, tariff_tables)

        (; loadHH, genPV) = params
        (; Buy, Sell, ChargeBESS, DischargeBESS, SocBESS, TotCost) = vars
        (; BalanceHH) = constraints
        (; TIME) = params

        optimize!(model)

        # Skip if model did not solve to optimality
        if termination_status(model) != MOI.OPTIMAL
            @warn "Model not optimal for load=$(load_p), gen=$(gen_p). Skipping."
            continue
        end

        run_counter += 1
        run_label = "run_$(run_counter)_load$(load_p)_fuse$(fuse_size)_bess$(bess_type)_gen$(gen_p)"

        # Initialise the DataFrame with the time column on the first successful run
        if isnothing(netload_df)
            netload_df = DataFrame(time = collect(TIME))
        end

        # Extract results
        netload_vals   = [round(value(Netload[t]),        digits=4) for t in TIME]
        # load_vals      = [round(value(loadHH[t]),           digits=4) for t in TIME]
        # gen_vals       = [round(value(genPV[t]),            digits=4) for t in TIME]
        # buy_vals       = [round(value(Buy[t]),              digits=4) for t in TIME]
        # sell_vals      = [round(value(Sell[t]),             digits=4) for t in TIME]
        # charge_vals    = [round(value(ChargeBESS[t]),       digits=4) for t in TIME]
        # discharge_vals = [round(value(DischargeBESS[t]),    digits=4) for t in TIME]
        # soc_vals       = [round(value(SocBESS[t]),          digits=4) for t in TIME]
        # mc_vals        = [round(shadow_price(BalanceHH[t]), digits=4) for t in TIME]
        total_cost     = round(value(TotCost),               digits=4)

        # # Full results CSV (appended row-wise as before)
        # case_df = DataFrame(
        #     load_profile  = fill(string(load_p),  length(TIME)),
        #     gen_profile   = fill(string(gen_p),   length(TIME)),
        #     total_cost    = fill(total_cost,      length(TIME)),
        #     time          = collect(TIME),
        #     load          = load_vals,
        #     gen           = gen_vals,
        #     buy           = buy_vals,
        #     sell          = sell_vals,
        #     netload       = netload_vals,
        #     charge_bess   = charge_vals,
        #     discharge_bess= discharge_vals,
        #     soc_bess      = soc_vals,
        #     marginal_cost = mc_vals,
        # )

        # # Append to CSV: write header only on first write
        # CSV.write(output_file, case_df; append=!first_write)
        # first_write = false

        # Netload CSV: add one column per run
        netload_df[!, Symbol(run_label)] = netload_vals

        println("  -> Done. Total cost = $total_cost")
    end

    # Write the wide netload table once at the end
    CSV.write(netload_file, netload_df)

    println("Netload profiles written to: $netload_file")
end