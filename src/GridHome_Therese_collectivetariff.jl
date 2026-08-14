using JuMP, HiGHS, Gurobi, PrettyTables, CSV, DataFrames, JSON3, Random
using Dates
const AxisArray = Containers.DenseAxisArray
const GRB_ENV = Gurobi.Env(output_flag = 0)

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

include(joinpath(@__DIR__, "inputdata.jl"))

function makeparameters(area::Symbol)
    (; price, profiles, facility_df, avg_power_tariff) = read_input_data()
    (; battery_cap, homeshare, tripenergy, chargeenergy, charger_power, public_charger_power, cost_public_charge, eta_chargeEV) = read_EV_data()

    # --- Model sets ---
    TIME    = 1:35040
    MONTH   = [:January, :February, :March, :April, :May, :June, :July, :August, :September, :October, :November, :December]

    # --- Model parameters ---
    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    HOUSEHOLDS    = load_profiles  # e.g. [:house_001, :house_002, ...]

    # EV parameters
    Random.seed!(RANDOM_SEED)
    ev_folder  = joinpath(raw"C:\Users\corte\Documents\GridHome\Input", "ev_data")
    good_ids   = JSON3.read(read(joinpath(ev_folder, "EVs_charging_at_home.txt"), String), Vector{String})
    ev_assignment = Dict(zip(load_profiles, shuffle(good_ids)))

    # Per-household parameters — stored as Dicts keyed by household id
    loadHH          = Dict{Symbol, Vector{Float64}}()
    maxpower        = Dict{Symbol, Float64}()
    sizeEV          = Dict{Symbol, Float64}()
    home            = Dict{Symbol, Vector{Float64}}()
    driving_demandEV = Dict{Symbol, Vector{Float64}}()
    logged_chargeEV  = Dict{Symbol, Vector{Float64}}()
    ev_ids           = Dict{Symbol, Union{Symbol,Nothing}}()

    for h in HOUSEHOLDS
        facility_row = filter(r -> r.facility_id == String(h), facility_df)
        if isempty(facility_row) || ismissing(facility_row[1, :contract_fuse_size])
            @warn "Skipping $h — missing facility entry or fuse size."
            continue
        end
        fuse_size     = facility_row[1, :contract_fuse_size]
        # maxpower[h]   = FUSE_TO_POWER[fuse_size]
        maxpower[h]   = fuse_size * FUSE_TO_POWER_FACTOR
        loadHH[h]     = profiles.loadHH[TIME, h]

        ev_id         = Symbol(ev_assignment[h])
        ev_ids[h]     = ev_id
        sizeEV[h]     = battery_cap[battery_cap.id .== String(ev_id), :capacity_kWh][1]
        home[h]       = homeshare[TIME, ev_id]
        driving_demandEV[h] = tripenergy[TIME, ev_id]
        logged_chargeEV[h]  = chargeenergy[TIME, ev_id]
    end

    # Model parameters
    power_tariff = avg_power_tariff                 # €/kW/month
    overload_tol = 0.10

    # Only keep households that were successfully loaded
    HOUSEHOLDS = [h for h in HOUSEHOLDS if haskey(loadHH, h)]

    # Electricity price for the selected area
    elprice = getproperty(price, area)[TIME]

    return (; TIME, MONTH, HOUSEHOLDS, area,
              loadHH, elprice, maxpower, overload_tol,
              sizeEV, home, driving_demandEV, logged_chargeEV, ev_ids,
              charger_power, public_charger_power, cost_public_charge, eta_chargeEV,
              power_tariff)
end

function makevariables(model, params)
    (; TIME, MONTH, HOUSEHOLDS,
       maxpower, overload_tol, sizeEV) = params

    @variables model begin
        TotCost
        0 <= Buy[h in HOUSEHOLDS, t in TIME]            <= maxpower[h] / 4 * (1 + overload_tol)     # kWh/15-min
        0 <= ChargeEV[h in HOUSEHOLDS, t in TIME]                                                   # kWh/15-min (kW/4)
        0 <= PublicChargeEV[h in HOUSEHOLDS, t in TIME]                                             # kWh/15-min (kW/4)
        0 <= SocEV[h in HOUSEHOLDS, t in TIME]          <= sizeEV[h]                                # kWh
        0 <= Peak[m in MONTH]                                                                       # kW — shared collective peak
    end

    return (; TotCost, Buy, ChargeEV, PublicChargeEV, SocEV, Peak)
end

function makeconstraints(model, vars, params)
    (; TIME, MONTH, HOUSEHOLDS, 
       loadHH, elprice, 
       charger_power, public_charger_power, home, 
       driving_demandEV, cost_public_charge, eta_chargeEV, 
       power_tariff) = params
    (; TotCost, Buy, ChargeEV, PublicChargeEV, SocEV, Peak) = vars

    @constraints model begin
        BalanceHH[h in HOUSEHOLDS, t in TIME],
            Buy[h, t] == loadHH[h][t] + ChargeEV[h, t]

        BalanceEV[h in HOUSEHOLDS, t in TIME],
            SocEV[h, t == TIME[end] ? TIME[1] : t+1] == SocEV[h, t] + (ChargeEV[h, t] * eta_chargeEV) + (PublicChargeEV[h, t] * eta_chargeEV) - driving_demandEV[h][t]      # Note: driving demand is NOW positive for energy consumed

        LimitChargeEV[h in HOUSEHOLDS, t in TIME],
            ChargeEV[h, t] <= charger_power / 4 * home[h][t]                      # kWh/15-min, only when the car is at home

        LimitPublicChargeEV[h in HOUSEHOLDS, t in TIME],
            PublicChargeEV[h, t] <= public_charger_power / 4 * (1-home[h][t])     # kWh/15-min, only when the car is NOT at home

        # Collective peak — driven by sum of all households
        PeakPower[m in MONTH, t in MONTH_TIMESTEPS[m]],
            Peak[m] >= sum(Buy[h, t] for h in HOUSEHOLDS) * 4                     # Convert back to kW for peak power calculation

        Totalcosts,
            TotCost == sum(Buy[h, t] * (elprice[t]) for h in HOUSEHOLDS, t in TIME) * kWh_to_MWh + 
                    sum(PublicChargeEV[h, t] * cost_public_charge for h in HOUSEHOLDS, t in TIME) * kWh_to_MWh + 
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
            "OutputFlag"     => 1,      # 0 for silent, 1 for verbose
            "BarHomogeneous" => 1,      # 0 for inhomogeneous, 1 for homogeneous
            "Crossover"      => 0,      # 0 for no crossover, 1 for crossover
            "Method"         => 2,
            "DualReductions" => 0,
        )
    else
        error("Unknown solver: $solver. Valid options are :HiGHS, :Gurobi.")
    end
end

function makemodel(area::Symbol, solver::Symbol)
    optimizer = set_solver(solver)
    model = Model(optimizer)

    t0 = time()
    params = makeparameters(area)

    println("diag | parameters seconds = ", round(time() - t0, digits=2))

    t1 = time()
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; TotCost) = vars

    @objective model Min begin
        TotCost
    end
    println("diag | build seconds = ", round(time() - t1, digits=2))
    println("diag | vars = ", JuMP.num_variables(model))
    println("diag | cons = ", JuMP.num_constraints(model; count_variable_in_set_constraints=false))

    return model, params, vars, constraints
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

    output_path = raw"C:\Users\corte\Documents\GridHome\Output\lowtariff"

    all_results = Dict{Tuple{Symbol,Symbol}, DataFrame}()

    for area in chosen_areas
        println("\n=============================== Running model for area: $area with collective tariff ==============================")
        
        output_folder = joinpath(output_path, "ThereseRuns", "Seed$(RANDOM_SEED)_$(area)_Tariff3")
        !isdir(output_folder) && mkpath(output_folder)

        model, params, vars, constraints = makemodel(area, solver)

        (; TIME, HOUSEHOLDS, loadHH, driving_demandEV, logged_chargeEV, eta_chargeEV, ev_ids) = params
        (; Buy, ChargeEV, PublicChargeEV, SocEV, TotCost) = vars

        set_time_limit_sec(model, 3600.0)
        t2 = time()
        optimize!(model)
        status = termination_status(model)

        println("diag | solve seconds = ", round(time() - t2, digits=2))
        println("diag | status = ", termination_status(model))
        println("diag | primal = ", primal_status(model), " | dual = ", dual_status(model))

        if status != MOI.OPTIMAL
            compute_conflict!(model)
            if get_attribute(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
                iis_model, _ = copy_conflict(model)
                print(iis_model)
            end
            error("Model not optimal: $status")
        end

        println("Total cost = $(round(value(TotCost), digits=2))")

        for h in HOUSEHOLDS
            ev_id = ev_ids[h]
            results_df = DataFrame(
                time             = collect(TIME),
                load             = [round(loadHH[h][t],                              digits=2) for t in TIME],
                buy              = [round(value(Buy[h,t]),                            digits=2) for t in TIME],
                baseline         = [round(loadHH[h][t] + logged_chargeEV[h][t],      digits=2) for t in TIME],
                demand_ev        = [round(driving_demandEV[h][t],                     digits=2) for t in TIME],
                logged_ev        = [round(logged_chargeEV[h][t],                      digits=2) for t in TIME],
                charge_ev        = [round(value(ChargeEV[h,t]) * eta_chargeEV,        digits=2) for t in TIME],
                public_charge_ev = [round(value(PublicChargeEV[h,t]) * eta_chargeEV,  digits=2) for t in TIME],
                soc_ev           = [round(value(SocEV[h,t]),                          digits=2) for t in TIME],
            )

            output_file = joinpath(output_folder, "GridHome_Therese_$(area)_$(h)_EV_$(ev_id)_Tariff3.csv")
            CSV.write(output_file, results_df)
            println("$h → $(output_file)")

            all_results[(area, h)] = results_df
        end
    end
    
    return all_results
end