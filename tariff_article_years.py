# Postprocessing script for tariff article 

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# --- CONSTANTS AND SETTINGS ---
COLORS = ["#FC7C84FF",  "#5971FA", "#C771F9", "#61AA52"]
LOGGED_COLOR = "#23610A"
VEHICLE_COUNT = 188

# --- DATA LOADING AND PREPROCESSING ---    
# Load household demand data 
timeStepsPerHour = 4
HouseholdDemand = pd.read_csv('sum_houseload_main_selection.csv', sep=',')['demand']/VEHICLE_COUNT * timeStepsPerHour # Convert from kWh to kW

Inc_2021 = True
Inc_2022 = True
Inc_2023 = True
Inc_2024 = True
Dynamic = True

daysPerYear = 365
day = np.arange(1, 25)  # Makes a vector of values 1:24
daytime = np.repeat(day, timeStepsPerHour)
yeartime = np.tile(daytime, daysPerYear)

# Load charging data for different years
Years = []
HomeChargingCostMini = []
FastChargingCostMini = []
HomeChargingCostMini_P = []
FastChargingCostMini_P = []
HomeChargingDaytime = []
HomeChargingDynamic = []
Hometime = []
HometimeP =[]
Fasttime = []
HometimeDaytime = []
HometimeDynamic = []

LoggedDemand = pd.read_csv('tripenergy_2.csv', sep=';')  # Assuming first column is index
LoggedCharging_detailed = pd.read_csv('chargeenergy_2.csv', sep=';')

if Inc_2021:
    home_2021 = pd.read_csv("all_home_charge_notariff_2021.csv")
    home_P_2021 = pd.read_csv("all_home_charge_allhours_2021.csv")
    home_Daytime_2021 = pd.read_csv("all_home_charge_daytime_2021.csv")
    home_Dynamic_2021 = pd.read_csv("all_home_charge_collective_2021.csv")
    Years.append('2021')

    #Calc total charging and average per price area
    total_home_2021 = home_2021.value.sum()
    numberOfPriceAreas = pd.unique(home_2021['priceareas']).size
    numberOfVehicles = pd.unique(home_2021['trsp']).size
    total_home_2021 = total_home_2021 / numberOfPriceAreas
    HomeChargingCostMini.append(total_home_2021)

    #Calc total charging and average per price area for power tariff case
    total_home_P_2021 = home_P_2021.value.sum()
    total_home_P_2021 = total_home_P_2021 / numberOfPriceAreas
    HomeChargingCostMini_P.append(total_home_P_2021)
    total_home_dynamic_2021 = home_Dynamic_2021.value.sum() / numberOfPriceAreas
    HomeChargingDynamic.append(total_home_dynamic_2021)
    total_home_timediff_2021 = home_Daytime_2021.value.sum() / numberOfPriceAreas
    HomeChargingDaytime.append(total_home_timediff_2021)

    #Calc charging per hour of day
    timestep_home_2021 = home_2021.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_P_2021 = home_P_2021.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_timediff_2021 = home_Daytime_2021.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_dynamic_2021 = home_Dynamic_2021.groupby('timestep').value.sum() / numberOfPriceAreas

    dfTimestepSums = pd.DataFrame({'timestep': timestep_home_2021.index, 'HourOfDay':yeartime, 'CostMini Charging': timestep_home_2021.values, 'CostMiniPTariffCharging': timestep_home_P_2021.values, 'CostMiniDaytimeCharging': timestep_home_timediff_2021.values, 'CostMiniDynamicCharging': timestep_home_dynamic_2021.values})
    hourly_charging_sum = dfTimestepSums.groupby('HourOfDay')['CostMini Charging'].sum() / (total_home_2021) * 100
    Hometime.append(hourly_charging_sum)
    hourly_charging_sum_P = dfTimestepSums.groupby('HourOfDay')['CostMiniPTariffCharging'].sum() / (total_home_P_2021) * 100
    HometimeP.append(hourly_charging_sum_P)
    hourly_charging_sum_timediff = dfTimestepSums.groupby('HourOfDay')['CostMiniDaytimeCharging'].sum() / (total_home_timediff_2021) * 100
    HometimeDaytime.append(hourly_charging_sum_timediff)
    hourly_charging_sum_dynamic = dfTimestepSums.groupby('HourOfDay')['CostMiniDynamicCharging'].sum() / (total_home_dynamic_2021) * 100
    HometimeDynamic.append(hourly_charging_sum_dynamic)

if Inc_2022:
    home_2022 = pd.read_csv("all_home_charge_notariff_2022.csv")
    home_P_2022 = pd.read_csv("all_home_charge_allhours_2022.csv")
    home_Daytime_2022 = pd.read_csv("all_home_charge_daytime_2022.csv")
    home_Dynamic_2022 = pd.read_csv("all_home_charge_collective_2022.csv")
    Years.append('2022')

    #Calc total charging and average per price area
    total_home_2022 = home_2022.value.sum()
    numberOfPriceAreas = pd.unique(home_2022['priceareas']).size
    numberOfVehicles = pd.unique(home_2022['trsp']).size
    total_home_2022 = total_home_2022 / numberOfPriceAreas
    HomeChargingCostMini.append(total_home_2022)
    total_daytime_2022 = home_Daytime_2022.value.sum() / numberOfPriceAreas
    total_dynamic_2022 = home_Dynamic_2022.value.sum() / numberOfPriceAreas

    #Calc total charging and average per price area for power tariff case
    total_home_P_2022 = home_P_2022.value.sum()
    total_home_P_2022 = total_home_P_2022 / numberOfPriceAreas
    HomeChargingCostMini_P.append(total_home_P_2022)
    HomeChargingDaytime.append(total_daytime_2022)
    HomeChargingDynamic.append(total_dynamic_2022)

    #Calc charging per hour of day
    timestep_home_2022 = home_2022.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_P_2022 = home_P_2022.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_timediff_2022 = home_Daytime_2022.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_dynamic_2022 = home_Dynamic_2022.groupby('timestep').value.sum() / numberOfPriceAreas

    dfTimestepSums = pd.DataFrame({'timestep': timestep_home_2022.index, 'HourOfDay':yeartime, 'CostMiniCharging': timestep_home_2022.values, 'CostMiniPTariffCharging': timestep_home_P_2022.values, 'CostMiniDaytimeCharging': timestep_home_timediff_2022.values, 'CostMiniDynamicCharging': timestep_home_dynamic_2022.values})
    hourly_charging_sum = dfTimestepSums.groupby('HourOfDay')['CostMiniCharging'].sum() / (total_home_2022) * 100
    Hometime.append(hourly_charging_sum)
    hourly_charging_sum_P = dfTimestepSums.groupby('HourOfDay')['CostMiniPTariffCharging'].sum() / (total_home_P_2022) * 100
    HometimeP.append(hourly_charging_sum_P)
    hourly_charging_sum_timediff = dfTimestepSums.groupby('HourOfDay')['CostMiniDaytimeCharging'].sum() / (total_daytime_2022) * 100
    HometimeDaytime.append(hourly_charging_sum_timediff)
    hourly_charging_sum_dynamic = dfTimestepSums.groupby('HourOfDay')['CostMiniDynamicCharging'].sum() / (total_dynamic_2022) * 100
    HometimeDynamic.append(hourly_charging_sum_dynamic)

if Inc_2023:
    home_2023 = pd.read_csv("all_home_charge_notariff_2023.csv")
    home_P_2023 = pd.read_csv("all_home_charge_allhours_2023.csv")
    home_Daytime_2023 = pd.read_csv("all_home_charge_daytime_2023.csv")
    home_Dynamic_2023 = pd.read_csv("all_home_charge_collective_2023.csv")
    Years.append('2023')

    numberOfPriceAreas = pd.unique(home_2023['priceareas']).size

    total_home_2023 = home_2023.value.sum()
    total_home_2023 = total_home_2023 / numberOfPriceAreas
    HomeChargingCostMini.append(total_home_2023)

    total_home_P_2023 = home_P_2023.value.sum()
    total_home_P_2023 = total_home_P_2023 / numberOfPriceAreas
    HomeChargingCostMini_P.append(total_home_P_2023)
    total_daytime_2023 = home_Daytime_2023.value.sum() / numberOfPriceAreas
    total_dynamic_2023 = home_Dynamic_2023.value.sum() / numberOfPriceAreas
    HomeChargingDaytime.append(total_daytime_2023)
    HomeChargingDynamic.append(total_dynamic_2023)

    # Calc charging per hour of day
    timestep_home_2023 = home_2023.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_P_2023 = home_P_2023.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_daytime_2023 = home_Daytime_2023.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_dynamic_2023 = home_Dynamic_2023.groupby('timestep').value.sum() / numberOfPriceAreas

    dfTimestepSums = pd.DataFrame({'timestep': timestep_home_2023.index, 'HourOfDay': yeartime,
                                   'CostMiniCharging': timestep_home_2023.values, 'CostMiniPTariffCharging': timestep_home_P_2023.values, 'CostMiniDaytimeCharging': timestep_home_daytime_2023.values, 'CostMiniDynamicCharging': timestep_home_dynamic_2023.values})
    hourly_charging_sum = dfTimestepSums.groupby('HourOfDay')['CostMiniCharging'].sum() / (total_home_2023) * 100
    Hometime.append(hourly_charging_sum)
    hourly_charging_sum_P = dfTimestepSums.groupby('HourOfDay')['CostMiniPTariffCharging'].sum() / (total_home_P_2023) * 100
    HometimeP.append(hourly_charging_sum_P)
    hourly_charging_sum_timediff = dfTimestepSums.groupby('HourOfDay')['CostMiniDaytimeCharging'].sum() / (total_daytime_2023) * 100
    HometimeDaytime.append(hourly_charging_sum_timediff)
    hourly_charging_sum_dynamic = dfTimestepSums.groupby('HourOfDay')['CostMiniDynamicCharging'].sum() / (total_dynamic_2023) * 100
    HometimeDynamic.append(hourly_charging_sum_dynamic)

if Inc_2024:
    No_P_tariff_2024 = pd.read_csv("all_home_charge_notariff_2024.csv")
    home_P_2024 = pd.read_csv("all_home_charge_allhours_2024.csv")
    Years.append('2024')

    numberOfPriceAreas = pd.unique(No_P_tariff_2024['priceareas']).size
    numberOfVehicles = pd.unique(No_P_tariff_2024['trsp']).size
    dynamic_2024 = pd.read_csv("all_home_charge_collective_2024.csv")
    total_home_2024_dynamic = dynamic_2024.value.sum() / numberOfPriceAreas

    timediff_2024 =  pd.read_csv("all_home_charge_daytime_2024.csv")
    total_home_2024_timediff = timediff_2024.value.sum() / numberOfPriceAreas

    total_home_2024 = No_P_tariff_2024.value.sum()
    total_home_2024 = total_home_2024 / numberOfPriceAreas
    HomeChargingCostMini.append(total_home_2024)
    total_home_P_2024 = home_P_2024.value.sum()
    total_home_P_2024 = total_home_P_2024 / numberOfPriceAreas
    HomeChargingCostMini_P.append(total_home_P_2024)
 
    # Calc charging per hour of day
    timestep_home_2024 = No_P_tariff_2024.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_home_P_2024 = home_P_2024.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_dynamic_2024 = dynamic_2024.groupby('timestep').value.sum() / numberOfPriceAreas
    timestep_timediff_2024 = timediff_2024.groupby('timestep').value.sum() / numberOfPriceAreas

    dfTimestepSums = pd.DataFrame({'timestep': timestep_home_2024.index, 'HourOfDay': yeartime,
                                   'CostMiniCharging': timestep_home_2024.values, 'CostMiniPTariffCharging': timestep_home_P_2024.values, 'DynamicPTariffCharging': timestep_dynamic_2024.values, 'TimediffCharging': timestep_timediff_2024.values})
    hourly_charging_sum = dfTimestepSums.groupby('HourOfDay')['CostMiniCharging'].sum() / (total_home_2024) * 100
    Hometime.append(hourly_charging_sum)
    hourly_charging_sum_P = dfTimestepSums.groupby('HourOfDay')['CostMiniPTariffCharging'].sum() / (total_home_P_2024) * 100
    HometimeP.append(hourly_charging_sum_P)
    hourly_charging_sum_dynamic = dfTimestepSums.groupby('HourOfDay')['DynamicPTariffCharging'].sum() / (total_home_2024_dynamic) * 100
    HometimeDynamic.append(hourly_charging_sum_dynamic)
    hourly_charging_sum_timediff = dfTimestepSums.groupby('HourOfDay')['TimediffCharging'].sum() / (total_home_2024_timediff) * 100
    HometimeDaytime.append(hourly_charging_sum_timediff)

    ev_used = pd.read_csv('ev_mapping.csv', sep=',')
    cars_included = pd.unique(ev_used['ev_id'])
    LoggedChargingFiltered = LoggedCharging_detailed[LoggedCharging_detailed.columns[LoggedCharging_detailed.columns.isin(cars_included)]]
    LoggedDemand = LoggedDemand.fillna(0)
    LoggedDemandFiltered = LoggedDemand[LoggedDemand.columns[LoggedDemand.columns.isin(cars_included)]]
    LoggedDemandFiltered[LoggedDemandFiltered >= 0] = 0  # Set positive values to 0
    LoggedDemandFiltered = LoggedDemandFiltered.abs()  # Take absolute values
    LoggedChargingFiltered = LoggedChargingFiltered.abs()  # Take absolute values
    TotalLoggedCharging = LoggedChargingFiltered.sum().sum()
    TotalLoggedDemand = LoggedDemandFiltered.sum().sum()
    LoggedperTimestep=LoggedChargingFiltered.sum(axis=1)
    
    print('LoggedperTimestep size and head:', LoggedperTimestep.size, LoggedperTimestep.head())
    dfTimestepSumsLogged = pd.DataFrame({'timestep': timestep_home_2024.index, 'HourOfDay': yeartime,
                                    'Logged Charging': LoggedperTimestep.values})
    hourly_charging_sum_logged = dfTimestepSumsLogged.groupby('HourOfDay')['Logged Charging'].sum() / (TotalLoggedCharging) * 100
    timestep_logged = dfTimestepSumsLogged.groupby('timestep')['Logged Charging'].sum()

    if Dynamic:
        timestep_dynamic_2024 = dynamic_2024.groupby('timestep').value.sum() / numberOfPriceAreas 
        #timestep_dynamic_2024_fast = dynamic_2024_fast.groupby('timestep').value.sum() / numberOfPriceAreas
        dfTimestepSumsDynamic = pd.DataFrame({'timestep': timestep_dynamic_2024.index, 'HourOfDay': yeartime,
                                       'DynamicPTariffCharging': timestep_dynamic_2024.values})
        hourly_charging_sum_dynamic = dfTimestepSumsDynamic.groupby('HourOfDay')['DynamicPTariffCharging'].sum() / (total_home_2024_dynamic) * 100 
        timestep_timediff_2024 = timediff_2024.groupby('timestep').value.sum() / numberOfPriceAreas
        dfTimestepSumsTimediff = pd.DataFrame({'timestep': timestep_timediff_2024.index, 'HourOfDay': yeartime,
                                       'TimediffPTariffCharging': timestep_timediff_2024.values})

        hourly_charging_sum_timediff = dfTimestepSumsTimediff.groupby('HourOfDay')['TimediffPTariffCharging'].sum() / (total_home_2024_timediff) * 100
        logged_to_csv=timestep_logged/numberOfVehicles*timeStepsPerHour
        
        #select weeks
        startweek=4
        endweek=startweek+2

        start_idx = timeStepsPerHour * 24 * (7 * startweek + 1)
        end_idx   = timeStepsPerHour * 24 * (7 * endweek + 1)


        fig, ax = plt.subplots(figsize=(10, 5))

        logged_slice   = timestep_logged.iloc[start_idx:end_idx].values
        home_slice     = timestep_home_2024.iloc[start_idx:end_idx].values
        timediff_slice = timestep_timediff_2024.iloc[start_idx:end_idx].values
        homeP_slice    = timestep_home_P_2024.iloc[start_idx:end_idx].values
        dynamic_slice  = timestep_dynamic_2024.iloc[start_idx:end_idx].values

        x = np.arange(len(logged_slice))

        ax.plot(x, logged_slice * timeStepsPerHour, label='Logged charging', linestyle='-', color='black', linewidth=1)
        ax.plot(x, home_slice * timeStepsPerHour, label='No tariff', linestyle='-', color=COLORS[0], linewidth=1)
        ax.plot(x, timediff_slice * timeStepsPerHour, label='Daytime tariff', linestyle='-', color=COLORS[2], linewidth=1)
        ax.plot(x, homeP_slice * timeStepsPerHour, label='All hours tariff', linestyle='-', color=COLORS[1], linewidth=1)
        ax.plot(x, dynamic_slice * timeStepsPerHour, label='Collective tariff', linestyle='-', color=COLORS[3], linewidth=1)

        max_dynamic = timestep_dynamic_2024.iloc[start_idx:end_idx].max()
        max_timediff = timestep_timediff_2024.iloc[start_idx:end_idx].max()
        max_home_P = timestep_home_P_2024.iloc[start_idx:end_idx].max()
        max_home = timestep_home_2024.iloc[start_idx:end_idx].max()
        max_logged = timestep_logged.iloc[start_idx:end_idx].max()

        ax.axhline(y=max_dynamic*timeStepsPerHour, color=COLORS[3], linestyle='--', linewidth=0.8)
        ax.axhline(y=max_home_P*timeStepsPerHour, color=COLORS[1], linestyle='--', linewidth=0.8)
        ax.axhline(y=max_timediff*timeStepsPerHour, color=COLORS[2], linestyle='--', linewidth=0.8)
        ax.axhline(y=max_home*timeStepsPerHour, color=COLORS[0], linestyle='--', linewidth=0.8)
        ax.axhline(y=max_logged*timeStepsPerHour, color='black', linestyle='--', linewidth=0.8)
        plot_timesteps = timeStepsPerHour*24*7*(endweek-startweek)
        # Create tick positions - one per day at noon
        num_days = int(np.ceil(plot_timesteps / (timeStepsPerHour*24)))
        tick_positions = [i * timeStepsPerHour*24 + timeStepsPerHour*12 for i in range(num_days + 1)]
        tick_positions = [pos for pos in tick_positions if pos < plot_timesteps]
        # Create tick labels - day of week labels
        days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        tick_labels = [days[i % 7] for i in range(len(tick_positions))]
        # Set the ticks
        ax.set_xticks(tick_positions)
        ax.set_xticklabels(tick_labels, rotation=45)
        ax.set_xlabel('Day of Week', fontsize=14)
        ax.set_ylabel('Total Charging Power [kW]', fontsize=14)
        #ax.set_title('Hourly Distribution of Home Charging (Selected Weeks)', fontsize=16)
        ax.legend(fontsize=12, loc='upper right')
        # Create second y-axis
        ax2 = ax.twinx()
        # Set up the second y-axis with simple multiplication of the first axis
        y_min, y_max = ax.get_ylim()
        ax2.set_ylim(y_min / numberOfVehicles, y_max / numberOfVehicles)
        ax2.set_ylabel(f'Average Charging Power[kW]', fontsize=14, color='black')
        ax2.tick_params(axis='y', labelcolor='black')
        plt.tight_layout()
        plt.savefig("2024_hourly_distribution_selected_week_3.png", dpi=300)

        print('Size of timestep_home_2024:', timestep_home_2024.size, 'Size of HouseholdDemand:', HouseholdDemand.size, 'Number of Vehicles:', numberOfVehicles)

        HometimeDaytime.append(hourly_charging_sum_timediff)
        HometimeDynamic.append(hourly_charging_sum_dynamic)

Yearone = Years[0]

if Yearone == '2021':
    cars_included = pd.unique(home_2021['trsp'])
elif Yearone == '2022':
    cars_included = pd.unique(home_2022['trsp'])
elif Yearone == '2023':
    cars_included = pd.unique(home_2023['trsp'])
    numberOfPriceAreas = pd.unique(home_2023['priceareas']).size
elif Yearone == '2024':
    cars_included = pd.unique(No_P_tariff_2024['trsp'])
    numberOfPriceAreas = pd.unique(No_P_tariff_2024['priceareas']).size
else:
    raise ValueError(f"Unexpected year value: {Yearone}")
                  
LoggedDemandFiltered = LoggedDemand[LoggedDemand.columns[LoggedDemand.columns.isin(cars_included)]]
LoggedDemandFiltered[LoggedDemandFiltered >= 0] = 0  # Set positive values to 0
LoggedDemandFiltered = LoggedDemandFiltered.abs()  # Take absolute values
LoggedChargingFiltered = LoggedChargingFiltered.abs()  # Take absolute values
TotalLoggedCharging = LoggedChargingFiltered.sum().sum()
TotalLoggedDemand = LoggedDemandFiltered.sum().sum()

dfTimestepSumsLogged = pd.DataFrame({'timestep': timestep_home_2024.index, 'HourOfDay': yeartime,
                                   'Logged Charging': LoggedChargingFiltered.sum(axis=1).values})
hourly_charging_sum_logged = dfTimestepSumsLogged.groupby('HourOfDay')['Logged Charging'].sum() / (TotalLoggedCharging) * 100

# Plot hourly charging for the different years
plt.figure(figsize=(7, 5))

for i in range(len(Years)):
    plt.plot(Hometime[i], label=f"{Years[i]}", linestyle='-', color=COLORS[i], linewidth=1)
plt.plot(hourly_charging_sum_logged, label='Logged charging', linestyle='--', color='black', linewidth=1)
plt.xlabel('Hour of Day', fontsize=14)
plt.ylabel('Share of Daily Charging [%]', fontsize=14)
plt.title('(a) No tariff', fontsize=16)
plt.xticks(np.arange(0, 25, 1))
plt.yticks(np.arange(0, 24, 2))
plt.ylim(0, 23)
plt.xlim(1, 24)
plt.legend(fontsize=12, loc='upper right')
plt.tight_layout()
plt.savefig(f"line_chart_hourly_home_charging_cost_mini.png", dpi=300)

#plot the same but with P-tariff
plt.figure(figsize=(7, 5))
for i in range(len(Years)):
    plt.plot(HometimeP[i], label=f"{Years[i]}", linestyle='-',color=COLORS[i], linewidth=1)
plt.plot(hourly_charging_sum_logged, label='Logged charging', linestyle='--', color='black', linewidth=1)
plt.xlabel('Hour of Day', fontsize=14)
plt.ylabel('Share of Daily Charging [%]', fontsize=14)
plt.title('(c) All hours tariff', fontsize=16)
plt.xticks(np.arange(0, 25, 1))
plt.xlim(1, 24)
plt.yticks(np.arange(0, 24, 2))
plt.ylim(0, 23)
plt.legend(fontsize=12, loc='upper right')
plt.tight_layout()

plt.savefig(f"line_chart_hourly_home_charging_comparison_P_tariff.png", dpi=300)

plt.figure(figsize=(7, 5))
for i in range(len(Years)):
    plt.plot(HometimeDaytime[i], label=f"{Years[i]}", linestyle='-',color=COLORS[i], linewidth=1)
plt.plot(hourly_charging_sum_logged, label='Logged charging', linestyle='--', color='black', linewidth=1)
plt.xlabel('Hour of Day', fontsize=14)
plt.ylabel('Share of Daily Charging [%]', fontsize=14)
plt.title('(b) Daytime tariff', fontsize=16)
plt.xticks(np.arange(0, 25, 1))
plt.xlim(1, 24)
plt.yticks(np.arange(0, 24, 2))
plt.ylim(0, 23)
plt.legend(fontsize=12, loc='upper right')
plt.tight_layout()
plt.savefig(f"line_chart_hourly_home_charging_comparison_daytime_P_tariff.png", dpi=300)

plt.figure(figsize=(7, 5))
for i in range(len(Years)):
    plt.plot(HometimeDynamic[i], label=f"{Years[i]}", linestyle='-',color=COLORS[i], linewidth=1)
plt.plot(hourly_charging_sum_logged, label='Logged charging', linestyle='--', color='black', linewidth=1)
plt.xlabel('Hour of Day', fontsize=14)
plt.ylabel('Share of Daily Charging [%]', fontsize=14)
plt.title('(d) Collective tariff', fontsize=16)
plt.xticks(np.arange(0, 25, 1))
plt.xlim(1, 24)
plt.yticks(np.arange(0, 24, 2))
plt.ylim(0, 23)
plt.legend(fontsize=12, loc='upper right')
plt.tight_layout()
plt.savefig(f"line_chart_hourly_home_charging_comparison_dynamic_P_tariff.png", dpi=300)

plt.show()

