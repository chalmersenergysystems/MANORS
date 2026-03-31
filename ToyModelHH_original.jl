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
    loadHH = profiles.loadHH[TIME, :profile_17]         # kWh/15-min
    genPV = profiles.genPVhh[TIME, :profile_15]         # kWh/15-min

    tariffHH, _, compensationPV = readtable(tariffparameters, AREA)

    sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS = readtable(batteryparameters, BESS)

    return (; TIME, AREA, loadHH, genPV, tariffHH, compensationPV, elprice2030, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS)
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
    (; TIME, loadHH, genPV, tariffHH, compensationPV, elprice2030, sizeBESS, rateBESS, eta_chargeBESS, eta_dischargeBESS) = params
    (; HHcost, Buy, Sell, NetloadHH, ChargeBESS, DischargeBESS, SocBESS) = vars
    
    @constraints model begin
        BalanceHH[t in TIME],
            genPV[t] + DischargeBESS[t] + Buy[t] >= loadHH[t] + ChargeBESS[t] + Sell[t]
        
        BalanceBESS[t in TIME[1:end-1]],
            SocBESS[t+1] <= SocBESS[t] + (ChargeBESS[t] * eta_chargeBESS[:BESS10]) - (DischargeBESS[t] / eta_dischargeBESS[:BESS10]) #- (lossesBESS[:BESS10] * SocBESS[t] / TIME[end])

        LoopBESS,
            SocBESS[1] == SocBESS[end]

        LimitsSocBESS[t in TIME],
            SocBESS[t] <= sizeBESS[:BESS10]

        LimitsChargeBESS[t in TIME], # kWh/15-min
            ChargeBESS[t] <= sizeBESS[:BESS10] * rateBESS[:BESS10] / 4
        
        LimitsDischargeBESS[t in TIME], # kWh/15-min
            DischargeBESS[t] <= sizeBESS[:BESS10] * rateBESS[:BESS10] / 4

        NetloadHHdef[t in TIME],
            NetloadHH[t] == Buy[t] - Sell[t]

        Totalcosts,
            HHcost == sum(Buy[t] * (elprice2030[t] + tariffHH[:SE3]) for t in TIME) - sum(Sell[t] * (elprice2030[t] + compensationPV[:SE3]) for t in TIME)
    end

    return (; BalanceHH, BalanceBESS, LimitsSocBESS, LimitsChargeBESS, LimitsDischargeBESS, NetloadHHdef, Totalcosts)
end

function makemodel()
    model = Model(HiGHS.Optimizer)

    params = makeparameters()
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; HHcost) = vars

    @objective model Min begin
        HHcost
    end

    return model, params, vars, constraints
end

function runmodel()
    ToyModelHH, params, vars, constraints = makemodel()

    (; loadHH, genPV) = params
    (; Buy, Sell, NetloadHH) = vars
    (; BalanceHH) = constraints
    TIME = params.TIME

    optimize!(ToyModelHH)

    # Extract optimized values and marginal costs
    load = [round(value(loadHH[t]), digits=2) for t in TIME]
    gen = [round(value(genPV[t]), digits=2) for t in TIME]
    buy = [round(value(Buy[t]), digits=2) for t in TIME]
    sell = [round(value(Sell[t]), digits=2) for t in TIME]
    netload = [round(value(NetloadHH[t]), digits=2) for t in TIME]
    marginal_cost = [round(JuMP.shadow_price(BalanceHH[t]), digits=2) for t in TIME]

    # Create results DataFrame
    results_df = DataFrame(time=TIME, load=load, gen=gen, buy=buy, sell=sell, netload=netload, marginal_cost=marginal_cost)
    
    output_path = raw"C:\Users\corte\Documents\REGAL_ToyModel\Output"
    CSV.write(joinpath(output_path, "ToyModelHH_results.csv"), results_df)

    return results_df
end