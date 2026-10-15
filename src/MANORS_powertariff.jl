using JuMP, HiGHS, Gurobi, PrettyTables, CSV, DataFrames, JSON3, Random
const AxisArray = Containers.DenseAxisArray
const GRB_ENV = Gurobi.Env(output_flag = 0)

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

include(joinpath(@__DIR__, "inputdata.jl"))

function makeparameters(load_profile, fuse_size, area::Symbol, ev_ids::Vector{Symbol}, tariff::Int)
    (; price, profiles, avg_power_tariff) = read_input_data()
    (; battery_cap, homeshare, tripenergy, chargeenergy, charger_power, public_charger_power, cost_public_charge, eta_chargeEV) = read_EV_data()

    # --- Model sets ---
    TIME = 1:35040
    DAYTIME = [t for t in TIME if (t - 1) % 96 in 28:79]            # only hours from 7 am to 8 pm
    MONTH = [:January, :February, :March, :April, :May, :June, :July, :August, :September, :October, :November, :December]

    # --- Model parameters ---
    elprice = getproperty(price, area)[TIME]                        # €/MWh, 15-min resolution
    loadHH = profiles.loadHH[TIME, load_profile]                    # kWh/15-min

    # EV parameters (per-EV Dicts; empty Dicts when EV = Symbol[])
    EV               = ev_ids
    sizeEV           = Dict(ev => battery_cap[battery_cap.id .== String(ev), :capacity_kWh][1] for ev in EV)
    home             = Dict(ev => homeshare[TIME, ev]    for ev in EV)
    driving_demandEV = Dict(ev => tripenergy[TIME, ev]   for ev in EV)
    logged_chargeEV  = Dict(ev => chargeenergy[TIME, ev] for ev in EV)

    # Household parameters
    # maxpower = FUSE_TO_POWER[fuse_size]             # kW, add 20 kW to ensure no infeasibility due to the fuse limit (since we want to analyze the effect of the EV without fuse limitations)
    maxpower = fuse_size * FUSE_TO_POWER_FACTOR    # kW, current (A) * tri-phase * voltage (kV)
    overload_tol = 0.10                             # overload tolerance

    # Power tariff sets and parameters (0) "No Tariff", (1) "Daytime Tariff", (2) "All Hours Tariff"
    if tariff == 0
        power_tariff = 0
        timeslices = TIME
    elseif tariff == 1
        power_tariff = avg_power_tariff             # €/kW/month, based on typical grid tariffs for households in Sweden
        timeslices = DAYTIME
    elseif tariff == 2
        power_tariff = avg_power_tariff             # €/kW/month, based on typical grid tariffs for households in Sweden
        timeslices = TIME
    end

    return (; TIME, EV, timeslices, MONTH, area, maxpower, overload_tol, loadHH, elprice, sizeEV, home, driving_demandEV, logged_chargeEV, charger_power, public_charger_power, cost_public_charge, eta_chargeEV, power_tariff)
end

function makevariables(model, params)
    (; TIME, EV, MONTH, maxpower, overload_tol, sizeEV) = params

    @variables model begin
        TotCost                                                                     # €/year
        0 <= Buy[t in TIME]            <= maxpower / 4 * (1 + overload_tol)         # kWh/15-min
        0 <= ChargeEV[t in TIME, ev in EV]                                          # kWh/15-min (kW/4)
        0 <= PublicChargeEV[t in TIME, ev in EV]                                    # kWh/15-min (kW/4)
        0 <= SocEV[t in TIME, ev in EV] <= sizeEV[ev]                               # kWh
        0 <= Peak[m in MONTH]                                                       # kW
    end

    return (; TotCost, Buy, ChargeEV, PublicChargeEV, SocEV, Peak)
end

function makeconstraints(model, vars, params)
    (; TIME, EV, timeslices, MONTH, loadHH, elprice, home, driving_demandEV, charger_power, public_charger_power, cost_public_charge, eta_chargeEV, power_tariff) = params
    (; TotCost, Buy, ChargeEV, PublicChargeEV, SocEV, Peak) = vars

    @constraints model begin
        BalanceHH[t in TIME],
            Buy[t] == loadHH[t] + sum(ChargeEV[t, ev] for ev in EV; init = 0.0)

        BalanceEV[t in TIME, ev in EV],
            SocEV[t == TIME[end] ? TIME[1] : t+1, ev] == SocEV[t, ev] + (ChargeEV[t, ev] * eta_chargeEV) + (PublicChargeEV[t, ev] * eta_chargeEV) - driving_demandEV[ev][t]      # Note: driving demand is NOW positive for energy consumed

        LimitChargeEV[t in TIME, ev in EV],
            ChargeEV[t, ev] <= charger_power / 4 * home[ev][t]                      # kWh/15-min, only when the car is at home (one charger per EV)

        LimitPublicChargeEV[t in TIME, ev in EV],
            PublicChargeEV[t, ev] <= public_charger_power / 4 * (1-home[ev][t])     # kWh/15-min, only when the car is NOT at home

        PeakPower[m in MONTH, t in intersect(MONTH_TIMESTEPS[m], timeslices)],
            Peak[m] >= Buy[t] * 4                                           # Convert back to kW for peak power calculation

        Totalcosts,
            TotCost == sum(Buy[t] * (elprice[t]) for t in TIME) * kWh_to_MWh + 
                    sum(PublicChargeEV[t, ev] * cost_public_charge for t in TIME, ev in EV; init = 0.0) * kWh_to_MWh + 
                    sum(Peak[m] * power_tariff for m in MONTH)
    end

    return (; BalanceHH, BalanceEV, 
              LimitChargeEV, LimitPublicChargeEV, 
              PeakPower, Totalcosts)
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

function makemodel(load_profile, fuse_size, area::Symbol, solver::Symbol, ev_ids::Vector{Symbol}, tariff::Int)
    optimizer = set_solver(solver)
    model = Model(optimizer)

    params = makeparameters(load_profile, fuse_size, area, ev_ids, tariff)
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; TotCost) = vars

    @objective model Min begin
        TotCost
    end

    return model, params, vars, constraints
end

function assign_evs(load_profiles, good_ids::Vector{String}, n_ev::Int)
    length(good_ids) >= n_ev || error("Only $(length(good_ids)) EV profiles available, cannot assign $n_ev EVs per household.")
    queue = String[]
    assignment = Dict{eltype(load_profiles), Vector{Symbol}}()
    for load_profile in load_profiles
        # When the queue cannot cover a household, draw a new seeded shuffle of the EVs not already in the queue (no duplicate EVs within a household)
        length(queue) < n_ev && append!(queue, shuffle(setdiff(good_ids, queue)))
        assignment[load_profile] = Symbol.(splice!(queue, 1:n_ev))
    end
    return assignment
end

function runmodel()
    # Prompt for solver selection
    print("Enter solver (HiGHS/Gurobi): ")
    solver_str = strip(readline())
    solver = Symbol(solver_str)
    solver ∉ (:HiGHS, :Gurobi) && error("Invalid solver: \"$solver_str\". Valid options are HiGHS, Gurobi.")

    # Prompt for area directly
    valid_areas = [:SE1, :SE2, :SE3, :SE4]
    println("Available areas: $(join(valid_areas, ", ")), or 'all'")
    print("Enter area (e.g. SE3 or 'all'): ")
    area_str = strip(readline())
    chosen_areas = area_str == "all" ? valid_areas : [Symbol(area_str)]
    if area_str != "all" && chosen_areas[1] ∉ valid_areas
        error("Invalid area: \"$area_str\". Valid options are SE1, SE2, SE3, SE4, all.")
    end

    # Prompt for tariff option
    tariff_options = [(0, "No Tariff"), (1, "Daytime Tariff"), (2, "All Hours Tariff")]
    println("Available tariff options: $(join(["$(opt[1]): $(opt[2])" for opt in tariff_options], ", "))")
    print("Enter tariff option (0-2): ")
    tariff_str = strip(readline())
    tariff = parse(Int, tariff_str)
    tariff ∉ (0, 1, 2) && error("Invalid tariff option: \"$tariff_str\". Valid options are 0 (No Tariff), 1 (Daytime Tariff), 2 (All Hours Tariff).")

    # Prompt for number of EVs per household
    print("Enter number of EVs per household (1-2): ")
    n_ev_str = strip(readline())
    n_ev = parse(Int, n_ev_str)
    n_ev ∉ (1, 2) && error("Invalid number of EVs: \"$n_ev_str\". Valid options are 1 or 2.")

    # Load input data once
    (; price, profiles, facility_df) = read_input_data()
    load_profiles = collect(Base.axes(profiles.loadHH, 2))

    # 16A households cannot handle 2 EVs: keep only households with a known fuse size > 16 A
    if n_ev == 2
        fuse_of(lp) = begin
            row = filter(r -> r.facility_id == String(lp), facility_df)
            isempty(row) ? missing : row[1, :contract_fuse_size]
        end
        n_before = length(load_profiles)
        load_profiles = filter(lp -> coalesce(fuse_of(lp) > 16, false), load_profiles)
        println("2 EVs per household: keeping $(length(load_profiles)) of $n_before load profiles (fuse size > 16 A).")
        isempty(load_profiles) && error("No load profiles with fuse size > 16 A.")
    end

    ev_folder = joinpath(INPUT_PATH, "ev_data")
    good_ids = JSON3.read(read(joinpath(ev_folder, "EVs_charging_at_home.txt"), String), Vector{String})

    length(good_ids) >= n_ev * length(load_profiles) || @warn "Fewer EV profiles ($(length(good_ids))) than needed ($(n_ev * length(load_profiles))) — EVs will be reused across households (new seeded shuffle each time the list is exhausted)."
    Random.seed!(RANDOM_SEED)
    ev_assignment = assign_evs(load_profiles, good_ids, n_ev)

    output_path = joinpath(OUTPUT_PATH, "Seed$(RANDOM_SEED)")
    ev_suffix = n_ev == 1 ? "" : "_$(n_ev)EV"

    all_results = Dict{Symbol, DataFrame}()

    for area in chosen_areas
        println("\n=============================== Running model for area: $area with tariff: $tariff and $n_ev EV(s) ==============================")

        output_folder = joinpath(output_path, "AllRuns", "Seed$(RANDOM_SEED)_$(area)_Tariff$(tariff)$(ev_suffix)")
        !isdir(output_folder) && mkpath(output_folder)

        for (i, load_profile) in enumerate(load_profiles)
            # Look up fuse size
            facility_row = filter(r -> r.facility_id == String(load_profile), facility_df)
            if isempty(facility_row)
                @warn "No facility entry for load profile \"$load_profile\", skipping."
                continue
            end
            fuse_size = facility_row[1, :contract_fuse_size]
            if ismissing(fuse_size)
                @warn "Missing fuse size for load profile \"$load_profile\", skipping."
                continue
            end

            ev_ids = ev_assignment[load_profile]

            println("\nRun $i/$(length(load_profiles)) | area=$area | load=$load_profile | fuse=$(fuse_size)A | EV=$(join(ev_ids, ", "))")
            println("----------------------------------------------------------------------------------------------------------------------")

            model, params, vars, constraints = makemodel(load_profile, fuse_size, area, solver, ev_ids, tariff)

            (; loadHH, EV, driving_demandEV, logged_chargeEV, eta_chargeEV, TIME) = params
            (; Buy, ChargeEV, PublicChargeEV, SocEV, TotCost) = vars

            optimize!(model)
            status = termination_status(model)

            if status != MOI.OPTIMAL
                compute_conflict!(model)
                if get_attribute(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
                    iis_model, _ = copy_conflict(model)
                    print(iis_model)
                end
                @warn "Model not optimal ($status) for load=$load_profile, EV=$(join(ev_ids, ", ")). Skipping."
                continue
            end

            total_cost            = round(value(TotCost),                       digits=2)
            load_vals             = [round(value(loadHH[t]),                   digits=2) for t in TIME]
            buy_vals              = [round(value(Buy[t]),                      digits=2) for t in TIME]
            baseline_vals         = [round(loadHH[t] + sum(logged_chargeEV[ev][t] for ev in EV), digits=2) for t in TIME]
            optimized_vals        = [round(value(Buy[t]),                      digits=2) for t in TIME] # temporarily defined like this, since Sell[t] is not defined in the current model

            results_df = DataFrame(
                time             = collect(TIME),
                load             = load_vals,
                buy              = buy_vals,
                baseline         = baseline_vals,
                optimized        = optimized_vals,
            )

            # Per-EV output columns: unsuffixed for 1 EV, _1/_2 for 2 EVs
            for (i_ev, ev) in enumerate(EV)
                col = n_ev == 1 ? "" : "_$i_ev"
                results_df[!, "demand_ev$col"]        = [round(driving_demandEV[ev][t],                 digits=2) for t in TIME]
                results_df[!, "logged_ev$col"]        = [round(logged_chargeEV[ev][t],                  digits=2) for t in TIME]
                results_df[!, "charge_ev$col"]        = [round(value(ChargeEV[t, ev]) * eta_chargeEV,       digits=2) for t in TIME]
                results_df[!, "public_charge_ev$col"] = [round(value(PublicChargeEV[t, ev]) * eta_chargeEV, digits=2) for t in TIME]
                results_df[!, "soc_ev$col"]           = [round(value(SocEV[t, ev]),                     digits=2) for t in TIME]
            end

            output_file = joinpath(output_folder, "MANORS_$(area)_$(load_profile)_EV_$(join(ev_ids, "_"))_Tariff$(tariff).csv")
            CSV.write(output_file, results_df)
            println("Total cost = $total_cost  →  $(output_file)")

            all_results[load_profile] = results_df
        end
    end

    return all_results
end