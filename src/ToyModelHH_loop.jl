using JuMP, HiGHS, PrettyTables
const AxisArray = Containers.DenseAxisArray

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

include("inputdata.jl")

function makeparameters(load_profile, gen_profile, bess_type)
    (; price, profiles) = read_input_data()
    (; tariffparameters, batteryparameters) = read_input_tables()

    # --- Model sets ---
    TIME = 1:35040
    AREA = [:SE1, :SE2, :SE3, :SE4]
    BESS = [:BESS6, :BESS10, :BESS13, :BESS20]

    # --- Model parameters ---
    elprice2030 = price.present[TIME]                   # €/MWh, 15-min resolution
    loadHH = profiles.loadHH[TIME, load_profile]        # kWh/15-min
    genPV = profiles.genPVhh[TIME, gen_profile]         # kWh/15-min

    tariffHH, _, compensationPV = readtable(tariffparameters, AREA)

    sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS = readtable(batteryparameters, BESS)

    return (; TIME, AREA, bess_type, loadHH, genPV, tariffHH, compensationPV, elprice2030, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS)
end

function makevariables(model, params)
    (; TIME) = params

    @variables model begin
        HHcost                                  # Mkr/year
        Buy[t in TIME] >= 0                     # kWh/15-min
        Sell[t in TIME] >= 0                    # kWh/15-min
        NetloadHH[t in TIME]                    # kWh/15-min, positive means net load, negative means net generation
        ChargeBESS[t in TIME] >= 0              # kW
        DischargeBESS[t in TIME] >= 0           # kW
        SocBESS[t in TIME] >= 0                 # kWh
    end

    return (; HHcost, Buy, Sell, NetloadHH, ChargeBESS, DischargeBESS, SocBESS)
end

function makeconstraints(model, vars, params)
    (; TIME, bess_type, loadHH, genPV, tariffHH, compensationPV, elprice2030, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS) = params
    (; HHcost, Buy, Sell, NetloadHH, ChargeBESS, DischargeBESS, SocBESS) = vars
    
    @constraints model begin
        BalanceHH[t in TIME],
            genPV[t] + DischargeBESS[t] + Buy[t] >= loadHH[t] + ChargeBESS[t] + Sell[t]
        
        BalanceBESS[t in TIME[1:end-1]],
            SocBESS[t+1] <= SocBESS[t] + (ChargeBESS[t] * eta_chargeBESS[bess_type]) - (DischargeBESS[t] / eta_dischargeBESS[bess_type]) #- (lossesBESS[bess_type] * SocBESS[t] / TIME[end])

        LoopBESS,
            SocBESS[1] == SocBESS[end]

        LimitsSocBESS[t in TIME],
            SocBESS[t] <= sizeBESS[bess_type]

        LimitsChargeBESS[t in TIME], # kWh/15-min
            ChargeBESS[t] <= sizeBESS[bess_type] * rateBESS[bess_type] / 4
        
        LimitsDischargeBESS[t in TIME], # kWh/15-min
            DischargeBESS[t] <= sizeBESS[bess_type] * rateBESS[bess_type] / 4

        NetloadHHdef[t in TIME],
            NetloadHH[t] == Buy[t] - Sell[t]

        Totalcosts,
            HHcost == sum(Buy[t] * (elprice2030[t] + tariffHH[:SE3]) for t in TIME) - sum(Sell[t] * (elprice2030[t] + compensationPV[:SE3]) for t in TIME)
    end

    return (; BalanceHH, BalanceBESS, LimitsSocBESS, LimitsChargeBESS, LimitsDischargeBESS, NetloadHHdef, Totalcosts)
end

function makemodel(load_profile, gen_profile, bess_type)
    model = Model(HiGHS.Optimizer)

    params = makeparameters(load_profile, gen_profile, bess_type)
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; HHcost) = vars

    @objective model Min begin
        HHcost
    end

    return model, params, vars, constraints
end

function runmodel()
    (; profiles, facility_df) = read_input_data()

    # Retrieve all profile column names
    load_profiles = collect(Base.axes(profiles.loadHH, 2))
    gen_profiles  = collect(Base.axes(profiles.genPVhh, 2))
    gen_pool = build_genPV_pools(gen_profiles)

    output_path  = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"
    # output_file  = joinpath(output_path, "ToyModelHH_results_all.csv")  # not used for now
    netload_file = joinpath(output_path, "ToyModelHH_netload.csv")

    # isfile(output_file)  && rm(output_file)   # not used for now
    isfile(netload_file) && rm(netload_file)

    # first_write = true   # not used for now
    run_counter = 0

    # Initialise the netload DataFrame on the first run
    netload_df = nothing

    for load_p in load_profiles
        # Look up fuse size and derive BESS type
        facility_row = filter(r -> r.facility_id == String(load_p), facility_df)
        if isempty(facility_row)
            @warn "No facility entry found for load profile $(load_p). Skipping."
            continue
        end
        fuse_size = facility_row[1, :contract_fuse_size]
        bess_type = fuse_to_bess(fuse_size)

        # Draw one genPV profile at random from the pool (placeholder until pools are defined)
        gen_p = rand(gen_pool)

        println("Running: load=$(load_p)  |  fuse=$(fuse_size)A  |  bess=$(bess_type)  |  gen=$(gen_p)")

        ToyModelHH, params, vars, constraints = makemodel(Symbol(load_p), Symbol(gen_p), bess_type)

        (; loadHH, genPV) = params
        (; Buy, Sell, NetloadHH, ChargeBESS, DischargeBESS, SocBESS, HHcost) = vars
        (; BalanceHH) = constraints
        (; TIME) = params

        optimize!(ToyModelHH)

        # Skip if model did not solve to optimality
        if termination_status(ToyModelHH) != MOI.OPTIMAL
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
        netload_vals   = [round(value(NetloadHH[t]),        digits=4) for t in TIME]
        # load_vals      = [round(value(loadHH[t]),           digits=4) for t in TIME]
        # gen_vals       = [round(value(genPV[t]),            digits=4) for t in TIME]
        # buy_vals       = [round(value(Buy[t]),              digits=4) for t in TIME]
        # sell_vals      = [round(value(Sell[t]),             digits=4) for t in TIME]
        # charge_vals    = [round(value(ChargeBESS[t]),       digits=4) for t in TIME]
        # discharge_vals = [round(value(DischargeBESS[t]),    digits=4) for t in TIME]
        # soc_vals       = [round(value(SocBESS[t]),          digits=4) for t in TIME]
        # mc_vals        = [round(shadow_price(BalanceHH[t]), digits=4) for t in TIME]
        total_cost     = round(value(HHcost),               digits=4)

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