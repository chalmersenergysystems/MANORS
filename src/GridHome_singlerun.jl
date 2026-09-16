using JuMP, HiGHS, Gurobi, PrettyTables, CSV, DataFrames, JSON3, Random
const AxisArray = Containers.DenseAxisArray
const GRB_ENV = Gurobi.Env(output_flag = 0)

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

include(joinpath(@__DIR__, "inputdata.jl"))

function makeparameters(load_profile, gen_profile, bess_type, area::Symbol, region::String, use_bess::Bool, ev_ids::Vector{Symbol}, v2g_id::Union{String, Nothing})
    (; price, profiles) = read_input_data()
    genPV_data = read_PV_data(region)
    (; battery_cap, homeshare, tripenergy, chargeenergy, charger_power, cost_public_charge, eta_chargeEV) = read_EV_data()
    (; tariffparameters, batteryparameters) = read_input_tables()

    # --- Model sets ---
    TIME = 1:35040
    AREA = [:SE1, :SE2, :SE3, :SE4]
    BESS = [:BESS6, :BESS10, :BESS13, :BESS20]
    EV   = ev_ids

    # --- Model parameters ---
    # Load and generation profiles
    loadHH = profiles.loadHH[TIME, load_profile]                    # kWh/15-min
    genPV = genPV_data[TIME, gen_profile]                           # kWh/15-min

    # Electricity price profile
    elprice = getproperty(price, area)[TIME]                        # €/MWh, 15-min resolution

    # Tariff parameters
    tariffHH, _, compensationPV = readtable(tariffparameters, AREA)

    # Battery parameters
    bess_on = use_bess ? 1 : 0
    sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS, dodBESS, costBESS, n_cyclesBESS, lifetimeBESS, sohBESS = readtable(batteryparameters, BESS)

    # EV parameters (per-EV Dicts; empty Dicts when EV = Symbol[])
    sizeEV           = Dict(ev => battery_cap[battery_cap.id .== String(ev), :capacity_kWh][1] for ev in EV)
    home             = Dict(ev => homeshare[TIME, ev]    for ev in EV)
    driving_demandEV = Dict(ev => tripenergy[TIME, ev]   for ev in EV)
    logged_chargeEV  = Dict(ev => chargeenergy[TIME, ev] for ev in EV)

    # V2G parameter (Binary parameter to activate V2G in the model; 1 = V2G enabled, 0 = V2G disabled)
    if v2g_id !== nothing
        v2g = 1
        eta_dischargeEV = eta_chargeEV
    else
        v2g = 0
        eta_dischargeEV = 1
    end

    # Household parameters
    maxpower = BESS_TO_POWER[bess_type]

    return (; TIME, AREA, EV, area, bess_type, maxpower, loadHH, genPV, tariffHH, compensationPV, elprice, bess_on, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS, dodBESS, costBESS, n_cyclesBESS, lifetimeBESS, sohBESS, sizeEV, home, driving_demandEV, logged_chargeEV, charger_power, cost_public_charge, eta_chargeEV, eta_dischargeEV, v2g)
end

function makevariables(model, params)
    (; TIME, EV) = params

    @variables model begin
        TotCost                                                                     # €/year
        0 <= Buy[t in TIME]            <= maxpower / 4 * (1 + overload_tol)         # kWh/15-min
        0 <= Sell[t in TIME]           <= maxpower / 4 * (1 + overload_tol)         # kWh/15-min
        0 <= ChargeBESS[t in TIME]                                                  # kWh/15-min (kW/4)
        0 <= DischargeBESS[t in TIME]                                               # kWh/15-min (kW/4)
        0 <= SocBESS[t in TIME]                                                     # kWh
        0 <= CalDegBESS                                                             # % capacity lost due to calendar degradation
        0 <= CycDegBESS                                                             # % capacity lost due to cycling
        0 <= ChargeEV[t in TIME, ev in EV]                                          # kWh/15-min (kW/4)
        0 <= PublicChargeEV[t in TIME, ev in EV]                                    # kWh/15-min (kW/4)
        0 <= DischargeEV[t in TIME, ev in EV]                                       # kWh/15-min (kW/4), only for extension with V2G
        0 <= SocEV[t in TIME, ev in EV] <= sizeEV[ev]                               # kWh
    end

    return (; TotCost, Buy, Sell, ChargeBESS, DischargeBESS, SocBESS, CalDegBESS, CycDegBESS, ChargeEV, PublicChargeEV, DischargeEV, SocEV)
end

function makeconstraints(model, vars, params)
    (; TIME, EV, area, bess_type, loadHH, genPV, tariffHH, compensationPV, elprice, bess_on,sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS, dodBESS, costBESS, n_cyclesBESS, lifetimeBESS, sohBESS, sizeBESS, home, driving_demandEV, charger_power, public_charger_power, cost_public_charge, eta_chargeEV, eta_dischargeEV, v2g) = params
    (; TotCost, Buy, Sell, ChargeBESS, DischargeBESS, SocBESS, CalDegBESS, CycDegBESS, ChargeEV, PublicChargeEV, DischargeEV, SocEV) = vars

    @constraints model begin
        BalanceHH[t in TIME],
            genPV[t] + DischargeBESS[t] + Buy[t] + sum(DischargeEV[t, ev] for ev in EV; init = 0.0) == loadHH[t] + ChargeBESS[t] + Sell[t] + sum(ChargeEV[t, ev] for ev in EV; init = 0.0)

        BalanceBESS[t in TIME],
            SocBESS[t == TIME[end] ? TIME[1] : t+1] <= SocBESS[t] + (ChargeBESS[t] * eta_chargeBESS[bess_type]) - (DischargeBESS[t] / eta_dischargeBESS[bess_type])

        LimitSocBESS[t in TIME],
            SocBESS[t] <= sizeBESS[bess_type] * dodBESS[bess_type] * bess_on                # kWh, limited by usable capacity when BESS is active

        LimitChargeBESS[t in TIME],
            ChargeBESS[t] <= sizeBESS[bess_type] * rateBESS[bess_type] / 4 * bess_on        # kWh/15-min

        LimitDischargeBESS[t in TIME],
            DischargeBESS[t] <= sizeBESS[bess_type] * rateBESS[bess_type] / 4 * bess_on     # kWh/15-min

        CalendarDegradationBESS,                                                                                                # % capacity lost due to calendar degradation, i.e: 40% lost over 10 years
            CalDegBESS == length(TIME) / (lifetimeBESS[bess_type] * 8760 * 4) * bess_on                                         # optimization horizon [15-min intervals] / lifetime [15-min intervals]
            # CalDegBESS == 0

        CycleDegradationBESS,                                                                                                   # % capacity lost per cycle, i.e. 40% lost over 6000 cycles
            CycDegBESS == sum(DischargeBESS[t] for t in TIME) / (sizeBESS[bess_type] * n_cyclesBESS[bess_type]) * bess_on       # cycles over optimization horizon / cycles to end of life or # discharged energy over optimization horizon [kWh] / energy throughput over N cycles [kWh] 
            # CycDegBESS == 0

        BalanceEV[t in TIME, ev in EV],
            SocEV[t == TIME[end] ? TIME[1] : t+1, ev] <= SocEV[t, ev] + (ChargeEV[t, ev] * eta_chargeEV * home[ev][t]) - (DischargeEV[t, ev] / eta_dischargeEV * home[ev][t]) + (PublicChargeEV[t, ev] * eta_chargeEV * (1-home[ev][t])) - driving_demandEV[ev][t]      # Note: driving demand is NOW positive for energy consumed

        LimitChargeEV[t in TIME, ev in EV],
            ChargeEV[t, ev] <= charger_power / 4 * home[ev][t]                  # kWh/15-min, only when the car is at home

        LimitDischargeEV[t in TIME, ev in EV],
            DischargeEV[t, ev] <= charger_power / 4 * home[ev][t] * v2g         # kWh/15-min, only when the car is at home, only if V2G enabled

        LimitPublicChargeEV[t in TIME, ev in EV],
            PublicChargeEV[t, ev] <= public_charger_power / 4 * home[ev][t]     # kWh/15-min, only when the car is at home

        Totalcosts,
            TotCost == sum(Buy[t] * (elprice[t]*1.25 + tariffHH[area]) for t in TIME) * kWh_to_MWh -
                    sum(Sell[t] * (elprice[t] + compensationPV[area]) for t in TIME) * kWh_to_MWh +
                    sum(PublicChargeEV[t, ev] * cost_public_charge for t in TIME, ev in EV; init = 0.0) * kWh_to_MWh +
                    (CalDegBESS + CycDegBESS) * costBESS[bess_type] * sizeBESS[bess_type] * (1 - sohBESS[bess_type]) * bess_on    
    end

    return (; BalanceHH, BalanceBESS, BalanceEV,
              LimitSocBESS, LimitChargeBESS, LimitDischargeBESS, 
              CalendarDegradationBESS, CycleDegradationBESS, 
              LimitChargeEV, LimitDischargeEV, LimitPublicChargeEV,
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

function makemodel(load_profile, gen_profile, bess_type, area::Symbol, region::String, solver::Symbol, use_bess::Bool, ev_ids::Vector{Symbol}, v2g_id::Union{String, Nothing})
    optimizer = set_solver(solver)
    model = Model(optimizer)

    params = makeparameters(load_profile, gen_profile, bess_type, area, region, use_bess, ev_ids, v2g_id)
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; TotCost) = vars

    @objective model Min begin
        TotCost
    end

    return model, params, vars, constraints
end

function runmodel()
    # Prompt for solver selection
    print("Enter solver (HiGHS/Gurobi): ")
    solver_str = strip(readline())
    solver = Symbol(solver_str)
    solver ∉ (:HiGHS, :Gurobi) && error("Invalid solver: \"$solver_str\". Valid options are HiGHS, Gurobi.")

    # Build region → area inverse lookup
    region_to_area = Dict(r => Symbol(a) for (a, rs) in gridarea_to_region for r in rs)
    all_regions = sort(collect(keys(region_to_area)))

    # Prompt for region; derive area from it
    println("Available regions: $(join(all_regions, ", "))")
    print("Enter region (e.g. Stockholm): ")
    region = String(strip(readline()))
    region ∉ all_regions && error("Invalid region: \"$region\". Run again to see available regions.")
    area = region_to_area[region]
    println("Derived area: $area")

    # Load input data
    (; price, profiles, facility_df) = read_input_data()
    genPV_data = read_PV_data(region)

    # Show available profiles, filtering gen profiles to the selected region
    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    gen_profiles  = collect(Base.axes(genPV_data, 2))
    isempty(gen_profiles) && error("No gen profiles found for region \"$region\" in area $area.")

    # Prompt for load profile
    print("Enter load profile (e.g. f88f1f56-0a4a-13a6-d241-02315fc5003d): ")
    load_str = strip(readline())
    load_profile = Symbol(load_str)
    load_profile ∉ load_profiles && error("Invalid load profile: \"$load_str\". Available load profiles: $(join(load_profiles, ", "))")

    # Prompt for gen profile
    print("Enter gen profile base name (e.g. x556): ")
    gen_str = strip(readline())
    gen_profile = Symbol(gen_str)
    gen_profile ∉ gen_profiles && error("Invalid gen profile: \"$gen_str\". Available gen profiles for $region: $(join(gen_profiles, ", "))")

    # Look up fuse size and derive BESS type
    facility_row = filter(r -> r.facility_id == String(load_profile), facility_df)
    isempty(facility_row) && error("No facility entry found for load profile \"$load_profile\".")
    fuse_size = facility_row[1, :contract_fuse_size]
    ismissing(fuse_size) && error("Missing fuse size for load profile \"$load_profile\".")
    bess_type = fuse_to_bess(fuse_size)

    # Prompt for BESS
    println("Run with BESS? (Yes/No): ")
    bess_answer = lowercase(strip(readline()))
    bess_answer ∉ ("yes", "no") && error("Invalid answer: \"$bess_answer\". Please enter 'Yes' or 'No'.")
    use_bess = (bess_answer == "yes")
    # if bess_answer == "yes"
    #     continue
    # else
    #     bess_type = "no_bess"
    #     sizeBESS = Dict("no_bess" => 0.0)
    # end

    println("\nRunning: region=$region  |  load=$load_profile  |  fuse=$(fuse_size)A  |  bess=$bess_type  |  gen=$gen_profile")
    println("----------------------------------------------------------------------------------------------------------------------")

    # Prompt for number of EVs
    print("How many EVs? (0–3): ")
    n_ev = parse(Int, strip(readline()))
    (n_ev < 0 || n_ev > 3) && error("Invalid number of EVs: $n_ev. Must be 0–3.")
    ev_folder = joinpath(INPUT_PATH, "ev_data")
    good_ids = JSON3.read(read(joinpath(ev_folder, "EVs_charging_at_home.txt"), String), Vector{String})
    ev_ids = Symbol.(shuffle(good_ids)[1:n_ev])
    isempty(ev_ids) ? println("No EVs selected.") : println("Selected EVs: $(join(ev_ids, ", "))")

    # Prompt for V2G option
    if isempty(ev_ids)
        println("Skipping V2G option.")
        v2g_id = nothing
    else
        print("Running with V2G? (Yes/No): ")
        v2g_answer = lowercase(strip(readline()))
        v2g_id = (v2g_answer == "yes") ? "v2g" : nothing
    end

    model, params, vars, constraints = makemodel(load_profile, gen_profile, bess_type, area, region, solver, use_bess, ev_ids, v2g_id)

    (; TIME, elprice, loadHH, genPV, sizeBESS, maxpower, EV, sizeEV, driving_demandEV, logged_chargeEV) = params
    (; Buy, Sell, ChargeBESS, DischargeBESS, SocBESS, ChargeEV, PublicChargeEV, DischargeEV, SocEV, TotCost) = vars
    (; BalanceHH) = constraints

    optimize!(model)
    status = termination_status(model)

    if status != MOI.OPTIMAL
        compute_conflict!(model)
        if get_attribute(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
            iis_model, _ = copy_conflict(model)
            print(iis_model)
        end
        @warn "Model not optimal ($status) for load=$load_profile, gen=$gen_profile. No results saved."
        return nothing
    end

    # Extract optimized values and marginal costs
    total_cost     = round(value(TotCost),                                                                          digits=2)
    load_vals      = [round(value(loadHH[t]),                                                                      digits=2) for t in TIME]
    gen_vals       = [round(value(genPV[t]),                                                                       digits=2) for t in TIME]
    buy_vals       = [round(value(Buy[t]),                                                                         digits=2) for t in TIME]
    sell_vals      = [round(value(Sell[t]),                                                                        digits=2) for t in TIME]
    netload_vals   = [round(value(Buy[t]) - value(Sell[t]),                                                        digits=2) for t in TIME]
    baseline_vals  = [round(loadHH[t] - genPV[t] + sum(logged_chargeEV[ev][t] for ev in EV; init=0.0),             digits=2) for t in TIME]
    charge_vals    = [round(value(ChargeBESS[t]),                                                                  digits=2) for t in TIME]
    discharge_vals = [round(value(DischargeBESS[t]),                                                               digits=2) for t in TIME]
    soc_vals       = [round(value(SocBESS[t]),                                                                     digits=2) for t in TIME]
    mc_vals        = [round(JuMP.shadow_price(BalanceHH[t]),                                                       digits=2) for t in TIME]

    results_df = DataFrame(
        time                = collect(TIME),
        load                = load_vals,
        gen                 = gen_vals,
        buy                 = buy_vals,
        sell                = sell_vals,
        netload             = netload_vals,
        baseline            = baseline_vals,
        charge_bess         = charge_vals,
        discharge_bess      = discharge_vals,
        soc_bess            = soc_vals,
        marginal_cost       = mc_vals,
    )

    # Per-EV output columns (_1, _2, _3)
    for (i, ev) in enumerate(EV)
        results_df[!, "demand_ev_$i"]        = [round(driving_demandEV[ev][t],      digits=2) for t in TIME]
        results_df[!, "logged_ev_$i"]        = [round(logged_chargeEV[ev][t],       digits=2) for t in TIME]
        results_df[!, "charge_ev_$i"]        = [round(value(ChargeEV[t, ev]) * eta_chargeEV[ev],       digits=2) for t in TIME]
        results_df[!, "discharge_ev_$i"]     = [round(value(DischargeEV[t, ev]) / eta_dischargeEV[ev],    digits=2) for t in TIME]
        results_df[!, "public_charge_ev_$i"] = [round(value(PublicChargeEV[t, ev]) * eta_chargeEV[ev], digits=2) for t in TIME]
        results_df[!, "soc_ev_$i"]           = [round(value(SocEV[t, ev]),          digits=2) for t in TIME]
    end

    output_path = joinpath(OUTPUT_PATH, "SingleRuns")
    bess_suffix = use_bess ? "" : "_NoBESS"
    ev_suffix = (n_ev == 0) ? "" : "_$(n_ev)EV"
    v2g_suffix = isnothing(v2g_id) ? "" : "_V2G"
    output_file = joinpath(output_path, "GridHome_final_singlerun_$(load_profile)_$(gen_profile)_$(region)$(bess_suffix)$(ev_suffix)$(v2g_suffix).csv")
    CSV.write(output_file, results_df)

    summary_file = joinpath(output_path, "GridHome_final_singlerun_$(load_profile)_$(gen_profile)_$(region)$(bess_suffix)$(ev_suffix)$(v2g_suffix)_summary.txt")

    open(summary_file, "w") do f
        println(f, "Single Run: region=$region | load=$load_profile | fuse=$(fuse_size)A | bess=$bess_type | gen=$gen_profile | $(ev_suffix)= $EV $(v2g_suffix)") 
        println(f, "-------------------------------------------------------------------------------------------------------------------------------------------")
        println(f, "Total cost = $total_cost €")
        println(f, "Revenue from solar PV = $(round(sum(value(Sell[t]) * elprice[t] for t in TIME) * kWh_to_MWh, digits=2)) €")
        if use_bess
            println(f, "Number of BESS cycles: $(round(sum(value(DischargeBESS[t]) for t in TIME) / sizeBESS[bess_type], digits=2))")
        else
            println(f, "Number of BESS cycles: n/a (BESS disabled)")
        end
        for ev in EV
            println(f, "Number of EV $ev battery cycles: $(round(sum(value(DischargeEV[t, ev]) for t in TIME; init=0.0) / sizeEV[ev], digits=2))")
            println(f, "Average daily V2G discharge: $(round(sum(value(DischargeEV[t, ev]) for t in TIME; init=0.0) / (length(TIME)/96), digits=2)) kWh/day")
        end
        n_buy_peak  = sum(value(Buy[t])  >= maxpower / 4 for t in TIME)
        n_sell_peak = sum(value(Sell[t]) >= maxpower / 4 for t in TIME)
        println(f, "Timesteps at max import power: $n_buy_peak & max export power: $n_sell_peak")
        println(f, "-------------------------------------------------------------------------------------------------------------------------------------------")
        println(f, "Results written to: $output_file")
    end

    return results_df
end