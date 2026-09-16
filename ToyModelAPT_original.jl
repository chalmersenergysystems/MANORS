using JuMP, HiGHS, PrettyTables
const AxisArray = Containers.DenseAxisArray

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

include("inputdata.jl")

function makeparameters()
    (; price, profiles) = read_input_data()
    (; tariffparameters, batteryparameters) = read_input_tables()

    # --- Model sets ---
    TIME = 1:35040
    AREA = [:SE1, :SE2, :SE3, :SE4]
    BESS = [:BESS6, :BESS10, :BESS13, :BESS20]

    # --- Model parameters ---
    elprice2030 = price.present[TIME]                   # €/MWh, 15-min resolution
    loadAPT1 = profiles.loadAPT[TIME, :profile_57]       # kWh/15-min
    loadAPT2 = profiles.loadAPT[TIME, :profile_17]       # kWh/15-min
    loadAPT3 = profiles.loadAPT[TIME, :profile_77]       # kWh/15-min
    genPV = profiles.genPVapt[TIME, :profile_10]          # kWh/15-min

    _, tariffAPT, compensationPV = readtable(tariffparameters, AREA)

    sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS = readtable(batteryparameters, BESS)

    return (; TIME, AREA, loadAPT1, loadAPT2, loadAPT3, genPV, tariffAPT, compensationPV, elprice2030, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS)
end

function makevariables(model, params)
    (; TIME) = params

    @variables model begin
        APTcost                                 # Mkr/year
        Buy[t in TIME] >= 0                     # kWh/15-min
        Sell[t in TIME] >= 0                    # kWh/15-min
        NetloadAPT[t in TIME]                   # kWh/15-min, positive means net load, negative means net generation
        ChargeBESS[t in TIME] >= 0              # kW
        DischargeBESS[t in TIME] >= 0           # kW
        SocBESS[t in TIME] >= 0                 # kWh
    end

    return (; APTcost, Buy, Sell, NetloadAPT, ChargeBESS, DischargeBESS, SocBESS)
end

function makeconstraints(model, vars, params)
    (; TIME, loadAPT1, loadAPT2, loadAPT3, genPV, tariffAPT, compensationPV, elprice2030, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS) = params
    (; APTcost, Buy, Sell, NetloadAPT, ChargeBESS, DischargeBESS, SocBESS) = vars
    
    @constraints model begin
        BalanceAPT[t in TIME],
            genPV[t] + DischargeBESS[t] + Buy[t] >= loadAPT1[t] + loadAPT2[t] + loadAPT3[t] + ChargeBESS[t] + Sell[t]
        
        BalanceBESS[t in TIME[1:end-1]],
            SocBESS[t+1] <= SocBESS[t] + (ChargeBESS[t] * eta_chargeBESS[:BESS6]) - (DischargeBESS[t] / eta_dischargeBESS[:BESS6]) #- (lossesBESS[:BESS10] * SocBESS[t] / TIME[end])

        LoopBESS,
            SocBESS[1] == SocBESS[end]

        LimitsSocBESS[t in TIME],
            SocBESS[t] <= sizeBESS[:BESS6]

        LimitsChargeBESS[t in TIME], # kWh/15-min
            ChargeBESS[t] <= sizeBESS[:BESS6] * rateBESS[:BESS6] / 4
        
        LimitsDischargeBESS[t in TIME], # kWh/15-min
            DischargeBESS[t] <= sizeBESS[:BESS6] * rateBESS[:BESS6] / 4

        NetloadAPTdef[t in TIME],
            NetloadAPT[t] == Buy[t] - Sell[t]

        Totalcosts,
            APTcost == sum(Buy[t] * (elprice2030[t] + tariffAPT[:SE3]) for t in TIME) - sum(Sell[t] * (elprice2030[t] + compensationPV[:SE3]) for t in TIME)
    end

    return (; BalanceAPT, BalanceBESS, LimitsSocBESS, LimitsChargeBESS, LimitsDischargeBESS, Totalcosts)
end

function makemodel()
    model = Model(HiGHS.Optimizer)

    params = makeparameters()
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; APTcost) = vars

    @objective model Min begin
        APTcost
    end

    return model, params, vars, constraints
end

function runmodel()
    ToyModelAPT, params, vars, constraints = makemodel()

    (; loadAPT1, loadAPT2, loadAPT3, genPV) = params
    (; Buy, Sell, NetloadAPT) = vars
    (; BalanceAPT) = constraints
    TIME = params.TIME

    optimize!(ToyModelAPT)

    # Extract optimized values and marginal costs
    load = [round(value(loadAPT1[t] + loadAPT2[t] + loadAPT3[t]), digits=2) for t in TIME]
    gen = [round(value(genPV[t]), digits=2) for t in TIME]
    buy = [round(value(Buy[t]), digits=2) for t in TIME]
    sell = [round(value(Sell[t]), digits=2) for t in TIME]
    netload = [round(value(NetloadAPT[t]), digits=2) for t in TIME]
    marginal_cost = [round(JuMP.shadow_price(BalanceAPT[t]), digits=2) for t in TIME]

    # Create results DataFrame
    results_df = DataFrame(time=TIME, load=load, gen=gen, buy=buy, sell=sell, netload=netload, marginal_cost=marginal_cost)

    output_path = joinpath(@__DIR__, "Output")
    CSV.write(joinpath(output_path, "ToyModelAPT_results.csv"), results_df)

    return results_df
end