import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
 
 # Set which figures to create
BarFiguresHomevsOther = True
HeatmapsCharging = True
StackedBars = True

ScatterEprice = True
PerEpriceareaSE3Only = False

#PerEpricearea is main, following is subset options
PerEpricearea = True
PerEpricehists = True

Year = "2024"

COLORS = ["#FC7C84FF",  "#5971FA", "#C771F9", "#61AA52"] 
LOGGED_COLOR = "#23610A" 
CMAP= "GnBu"
VEHICLE_COUNT = 188

alpha_hists = 1.0
alpha_bars = 1.0
alpha_scatters = 0.1

# Define case parameters
Temporal_resolution = '15_min'

# Load data
name2 = f"all_home_charge_notariff_{Year}.csv"
name2b= f"all_public_charge_notariff_{Year}.csv"
casename2 = 'Cost-minimized EV Charging, spotprice only'
NoPTariff = pd.read_csv(name2)
NoPTariffFast = pd.read_csv(name2b)

name3 = f"all_home_charge_allhours_{Year}.csv"
name3b = f"all_public_charge_allhours_{Year}.csv"
casename3 = 'Cost-minimized EV Charging, with P tariff all hours'
PTariff = pd.read_csv(name3)
PTariffFast = pd.read_csv(name3b)

name4 = f"all_home_charge_collective_{Year}.csv"
name4b = f"all_public_charge_collective_{Year}.csv"
casename4 = 'Cost-minimized EV Charging, with collective P tariff'
Collective = pd.read_csv(name4)
CollectiveFast = pd.read_csv(name4b)

name5 = f"all_home_charge_daytime_{Year}.csv"
name5b = f"all_public_charge_daytime_{Year}.csv"
casename5 = 'Cost-minimized EV Charging, with daytime Power Tariff'
TimeDiff = pd.read_csv(name5)
TimeDiffFast = pd.read_csv(name5b)

# Calculate key parameters
numberOfVehicles = pd.unique(NoPTariff['trsp']).size
numberOfPriceAreas = pd.unique(NoPTariff['priceareas']).size
TotalEnergyNoPTariff = NoPTariff.value.sum() / (numberOfPriceAreas)
TotalEnergyNoPTariffFast = NoPTariffFast.value.sum() / (numberOfPriceAreas)
TotalEnergyPTariff = PTariff.value.sum() / (numberOfPriceAreas)
TotalEnergyPTariffFast = PTariffFast.value.sum() / (numberOfPriceAreas)
TotalEnergyCollective = Collective.value.sum() / (numberOfPriceAreas)
TotalEnergyCollectiveFast = CollectiveFast.value.sum() / (numberOfPriceAreas)
TotalEnergyTimeDiff = TimeDiff.value.sum() / (numberOfPriceAreas)
TotalEnergyTimeDiffFast = TimeDiffFast.value.sum() / (numberOfPriceAreas)

# Load reference data
HouseholdDemand = pd.read_csv('sum_houseload_main_selection.csv', sep=',')['demand']/VEHICLE_COUNT
LoggedCharging = pd.read_csv('chargeenergy_2.csv', sep=';')
LoggedDemand = pd.read_csv('tripenergy_2.csv', sep=';')  # Assuming first column is index

# Unit Conversion and cleanup of reference data if needed
LoggedDemand = LoggedDemand.fillna(0)
LoggedDemand[LoggedDemand > 0] = 0  # Remove positive values if any
LoggedDemand = (LoggedDemand.abs()) / 0.95  # Make all values positive and assume charging efficiency of 95%
LoggedCharging = LoggedCharging.abs()  # Make all values positive

PeakIndividual = pd.read_csv('individual_peaks_Seed18_main_selection.csv', usecols=['Month', 'All hours'])

#Remove cars from logged data if not included in the optimized charging
ev_used = pd.read_csv('ev_mapping.csv', sep=',')
CarsIncluded = pd.unique(ev_used['ev_id'])
print('Cars included in the analysis:', CarsIncluded.size)
mapping = dict(zip(ev_used['ev_id'], ev_used['profile']))
LoggedCharging = LoggedCharging[LoggedCharging.columns[LoggedCharging.columns.isin(CarsIncluded)]]
LoggedDemand = LoggedDemand[LoggedDemand.columns[LoggedDemand.columns.isin(CarsIncluded)]]
print('Cars included in the logged data:', LoggedCharging.columns.size)
LoggedCharging = LoggedCharging.rename(columns=mapping)
LoggedDemand = LoggedDemand.rename(columns=mapping)

# Load Electricity prices
Eprices = pd.read_csv(f"AuctionPrice_{Year}_DayAhead_SE1,SE2,SE3,SE4_EUR_None.csv",sep=';')
Eprices = Eprices.iloc[:8760]

# Calculate the share of total logged charging and per vehicle
DemandPerVehicle = LoggedDemand.sum(axis=0)
TotalEnergyDemand = (LoggedDemand.sum(axis=1).sum())
TotalEnergyDemandMWh = TotalEnergyDemand / 1000  # Convert to MWh
TotalEnergyLogged = LoggedCharging.sum(axis=1).sum() 
LoggedChargingPerVehicle = LoggedCharging.sum(axis=0)
ShareOfChargingPerVehicle = LoggedChargingPerVehicle / DemandPerVehicle * 100
LoggedFastCharging = TotalEnergyDemand - TotalEnergyLogged
TotalShareOfHomeChargingLogged = TotalEnergyLogged / TotalEnergyDemand * 100  # Share of home charging in total charging

#Create vectors for the total home charging and fast charging
#HomeCharging = [LoggedChargingTotalSC, CostMiniTotalSC, CostMiniPTariffTotalSC]
HomeCharging = [TotalEnergyLogged, TotalEnergyNoPTariff, TotalEnergyTimeDiff, TotalEnergyPTariff, TotalEnergyCollective]

HomeCharging = np.array(HomeCharging)  # Convert to numpy array for division
HomeCharging = HomeCharging / 1000 # Convert to MWh
#FastCharging = [LoggedFastCharging, CostminiFastTotalSC, CostMiniPTariffFastTotalSC]  # Total fast charging in kWh
FastCharging = [LoggedFastCharging, TotalEnergyPTariffFast, TotalEnergyTimeDiffFast, TotalEnergyNoPTariffFast, TotalEnergyCollectiveFast]  # Total fast charging in kWh
FastCharging = np.array(FastCharging)  # Convert to numpy array for division
FastCharging = FastCharging / 1000  # Convert to MWh
TotalCharging = HomeCharging + FastCharging  # Total charging in MWh
ShareOfHomeCharging = HomeCharging / TotalCharging * 100  # Share of home charging in total charging
ShareOfFastCharging = FastCharging / TotalCharging * 100  # Share of fast charging in total charging

dfCharging = pd.DataFrame({
    'Home Charging': HomeCharging,  'Fast Charging': FastCharging, 'Share of Home Charging': ShareOfHomeCharging,
    'Share of Fast Charging': ShareOfFastCharging, 'Total Charging': TotalCharging
#}, index=['Logged Charging','Cost Minimized', 'Cost Minimized with Power Tariff'])
}, index=['Logged charging','No tariff', 'Daytime tariff', 'All hours tariff', 'Collective tariff'])
# }, index=['Logged Charging','Cost Minimized', 'Cost Mini with P Tariff', 'BabyTM'])
print('Share of Home Charging', dfCharging['Share of Home Charging'])

print('Total charging in MWh:', dfCharging['Total Charging'])

if BarFiguresHomevsOther:
    # Plot the share of charging at home vs at other locations for each case
    plt.figure(figsize=(7, 5))
    width = 0.6  # Width of the bars
    plt.bar(dfCharging.index, dfCharging['Share of Home Charging'], width, label='Home Location', color=COLORS[3], alpha=alpha_bars)
    plt.bar(dfCharging.index, dfCharging['Share of Fast Charging'], width, bottom=dfCharging['Share of Home Charging'], label='Other Location', color=LOGGED_COLOR, alpha=alpha_bars)

    plt.title('Distribution of charging', fontsize=16)
    plt.xlabel('Case', fontsize=14)
    plt.ylabel('Share of Total Charging [%]', fontsize=14) 
    plt.legend(['Home Location', 'Other Location'], loc='lower left', fontsize=12)
    plt.tight_layout()
    plt.savefig("Share_total_charging.png", dpi=300)

print('Total demand', TotalEnergyDemand, 'Total cost minimized charging:', TotalEnergyNoPTariff,'kWh', 'Total cost minimized fast charging:', TotalEnergyNoPTariffFast, 'kWh','Total cost minimized charging with power tariff:', TotalEnergyPTariff, 'kWh', 'Total fast charging with P tariff:', TotalEnergyPTariffFast, 'kWh', 'Total logged charging:', TotalEnergyLogged, 'kWh')
ChargingDiff=(TotalEnergyPTariff - TotalEnergyNoPTariff)/ TotalEnergyNoPTariff * 100
print('Decrease in charging', ChargingDiff, '%')

# --- Annual cost for logged charging (EV charging only), all 4 price areas ---
ev_15min_total_kwh = LoggedCharging.sum(axis=1).values

# Aggregate to hourly kWh (8760 hours expected)
if ev_15min_total_kwh.size == 8760 * 4:
    ev_hourly_kwh = ev_15min_total_kwh.reshape(-1, 4).sum(axis=1)  # shape (8760,)
else:
    ev_hourly_kwh = pd.Series(ev_15min_total_kwh).groupby(np.arange(ev_15min_total_kwh.size)//4).sum().values

# Ensure Eprices has 8760 rows and matching order
Eprices_hourly = Eprices.iloc[:ev_hourly_kwh.size]

price_cols = ['SE1 Price (EUR)', 'SE2 Price (EUR)', 'SE3 Price (EUR)', 'SE4 Price (EUR)']
logged_costs_per_vehicle = {}

for col in price_cols:
    price_per_kwh = Eprices_hourly[col].values / 1000.0   # EUR/MWh -> EUR/kWh
    total_cost = (ev_hourly_kwh * price_per_kwh).sum()   # EUR (all vehicles)
    logged_costs_per_vehicle[col] = total_cost / VEHICLE_COUNT

df_logged_costs = pd.DataFrame({
    'Cost per vehicle (EUR)': logged_costs_per_vehicle
})
print("Logged charging annual costs:")
print(df_logged_costs)


# --- Annual cost for household only demand, all 4 price areas ---
if len(HouseholdDemand) == 8760*4:
    house_hour = HouseholdDemand.values.reshape(-1, 4).sum(axis=1)   # shape (8760,), kWh per hour
else:
    house_hour = HouseholdDemand.groupby((HouseholdDemand.index) // 4).sum().values

# Identify price columns (EUR/MWh) and compute costs
price_cols = [c for c in Eprices.columns if 'Price' in c]
annual_cost_per_household = {}

for col in price_cols:
    price_per_kwh = Eprices[col].values / 1000.0   # EUR/MWh -> EUR/kWh
    cost_year = (house_hour * price_per_kwh).sum()  # EUR
    annual_cost_per_household[col] = cost_year 

print("Annual cost per household (without EV charging):", annual_cost_per_household)

# Time resolution setup
if Temporal_resolution == '10_min':
    timestepsPerH = 6
    daysPerYear = 365
    daysInFeb = 28 
elif Temporal_resolution == '15_min':
    timestepsPerH = 4
    daysPerYear = 365
    daysInFeb = 28
else:
    timestepsPerH = 1
    daysPerYear = 366
    daysInFeb = 29

# Sum values per timestep, i.e., over timesteps and vehicles for optimized and over vehicles for logged data
timestepSumsCostMini = NoPTariff.groupby('timestep')['value'].sum()
#print(timestep_sums.head())  # Show first few sums
timestepSumsPTariff = PTariff.groupby('timestep')['value'].sum()
#print(timestep_sums_PTariff.head())  # Show first few sums
timestepSumsTimeDiff = TimeDiff.groupby('timestep')['value'].sum()
timestepSumsCommon = Collective.groupby('timestep')['value'].sum()

timestepSumLogged = LoggedCharging.sum(axis=1)
#print(timestepSumLogged.head())  # Show first few sums

# Create time references
day = np.arange(1, 25)  # 1:24
daytime = np.repeat(day, timestepsPerH)
yeartime = np.tile(daytime, daysPerYear)
hours = np.arange(1, 8761) # 1:8760 or 1:8784
hourtime = np.repeat(hours, timestepsPerH)

# Create month indicators
Jan = np.ones(timestepsPerH * 24 * 31) * 1
Feb = np.ones(timestepsPerH * 24 * daysInFeb) * 2
Mar = np.ones(timestepsPerH * 24 * 31) * 3
Apr = np.ones(timestepsPerH * 24 * 30) * 4
May = np.ones(timestepsPerH * 24 * 31) * 5  
Jun = np.ones(timestepsPerH * 24 * 30) * 6
Jul = np.ones(timestepsPerH * 24 * 31) * 7
Aug = np.ones(timestepsPerH * 24 * 31) * 8
Sep = np.ones(timestepsPerH * 24 * 30) * 9
Oct = np.ones(timestepsPerH * 24 * 31) * 10  
Nov = np.ones(timestepsPerH * 24 * 30) * 11
Dec = np.ones(timestepsPerH * 24 * 31) * 12

# Concatenate months
Yearmonth = np.concatenate([Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec])

# Create a DataFrame for the time vectors
print('sizes of inputs:', timestepSumsCostMini.index.size, Yearmonth.size, yeartime.size, hourtime.size, timestepSumsPTariff.values.size, timestepSumLogged.values.size, HouseholdDemand.size, timestepSumsCommon.values.size, timestepSumsTimeDiff.values.size)
#dfTimestepSums = pd.DataFrame({'timestep': timestepSumsCostMini.index, 'PartOfMonth': Yearmonth, 'HourOfDay':yeartime, 'HourOfYear':hourtime,  'CostMiniCharging': timestepSumsCostMini.values, 'CostMiniPTariffCharging': timestepSumsPTariff.values, 'LoggedCharging': timestepSumLogged.values, 'HouseholdDemand': HouseholdDemand.demand.values, 'CostMiniCommonCharging': timestepSumsCommon.values, 'TimeDiffCharging': timestepSumsTimeDiff.values})
dfTimestepSums = pd.DataFrame({'timestep': timestepSumsCostMini.index, 'PartOfMonth': Yearmonth, 'HourOfDay':yeartime, 'HourOfYear':hourtime,  'CostMiniCharging': timestepSumsCostMini.values, 'CostMiniPTariffCharging': timestepSumsPTariff.values, 'LoggedCharging': timestepSumLogged.values, 'HouseholdDemand': HouseholdDemand, 'CostMiniCommonCharging': timestepSumsCommon.values, 'TimeDiffCharging': timestepSumsTimeDiff.values})

#dfTimestepSums = pd.DataFrame({'timestep': timestepSumsCostMini.index, 'PartOfMonth': Yearmonth, 'HourOfDay':yeartime, 'HourOfYear':hourtime,  'CostMiniCharging': timestepSumsCostMini.values, 'CostMiniPTariffCharging': timestepSumsPTariff.values, 'LoggedCharging': timestepSumLogged.values, 'HouseholdDemand': HouseholdDemand.demand.values})

#print(dfTimestepSums.head())

# Sum values based on hour of year
hourOfYearLogged = dfTimestepSums.groupby('HourOfYear')['LoggedCharging'].sum() / numberOfVehicles
print(hourOfYearLogged.head())
hourOfYearCostMini = dfTimestepSums.groupby('HourOfYear')['CostMiniCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)
hourOfYearPTariff = dfTimestepSums.groupby('HourOfYear')['CostMiniPTariffCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)
hourOfYearHouse = dfTimestepSums.groupby('HourOfYear')['HouseholdDemand'].sum()
hourOfYearCommon = dfTimestepSums.groupby('HourOfYear')['CostMiniCommonCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)
hourOfYearTimeDiff = dfTimestepSums.groupby('HourOfYear')['TimeDiffCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)

# Create a pivot table - Hours as rows, Months as columns
hourlyMonthlySumsCostMini = pd.pivot_table(dfTimestepSums, values='CostMiniCharging', index='HourOfDay', columns='PartOfMonth', aggfunc='sum')
hourlyMonthlySumsPTariff = pd.pivot_table(dfTimestepSums, values='CostMiniPTariffCharging', index='HourOfDay', columns='PartOfMonth', aggfunc='sum')
hourlyMonthlySumsLogged = pd.pivot_table(dfTimestepSums, values='LoggedCharging', index='HourOfDay', columns='PartOfMonth', aggfunc='sum')
hourlyMonthlySumsHouse = pd.pivot_table(dfTimestepSums, values='HouseholdDemand', index='HourOfDay', columns='PartOfMonth', aggfunc='sum')

hourlyMonthlySumsCommon = pd.pivot_table(dfTimestepSums, values='CostMiniCommonCharging', index='HourOfDay', columns='PartOfMonth', aggfunc='sum')

hourlyMonthlySumsTimeDiff = pd.pivot_table(dfTimestepSums, values='TimeDiffCharging', index='HourOfDay', columns='PartOfMonth', aggfunc='sum')


#Rename the columns to month names
month_names = {
    1: 'Jan', 2: 'Feb', 3: 'Mar', 4: 'Apr', 5: 'May', 6: 'Jun',
    7: 'Jul', 8: 'Aug', 9: 'Sep', 10: 'Oct', 11: 'Nov', 12: 'Dec'
}

PeakIndividual['Month'] = PeakIndividual['Month'].replace({f'm{i}': month for i, month in month_names.items()})
PeakIndividual['Month'] = pd.Categorical(PeakIndividual['Month'], categories=list(month_names.values()), ordered=True)

hourlyMonthlySumsCostMini = hourlyMonthlySumsCostMini.rename(columns=month_names)
hourlyMonthlySumsPTariff = hourlyMonthlySumsPTariff.rename(columns=month_names)
hourlyMonthlySumsLogged = hourlyMonthlySumsLogged.rename(columns=month_names)
hourlyMonthlySumsHouse = hourlyMonthlySumsHouse.rename(columns=month_names)
hourlyMonthlySumsCommon = hourlyMonthlySumsCommon.rename(columns=month_names)
hourlyMonthlySumsTimeDiff = hourlyMonthlySumsTimeDiff.rename(columns=month_names)

# Divide each column by the corresponding number of days in that month
days_in_month = {
    'Jan': 31, 'Feb': daysInFeb, 'Mar': 31, 'Apr': 30, 'May': 31, 'Jun': 30,
    'Jul': 31, 'Aug': 31, 'Sep': 30, 'Oct': 31, 'Nov': 30, 'Dec': 31
}
for month, days in days_in_month.items():
    if month in hourlyMonthlySumsCostMini.columns:
        hourlyMonthlySumsCostMini[month] = hourlyMonthlySumsCostMini[month] / days
        hourlyMonthlySumsPTariff[month] = hourlyMonthlySumsPTariff[month] / days
        hourlyMonthlySumsLogged[month] = hourlyMonthlySumsLogged[month] / days
        hourlyMonthlySumsHouse[month] = hourlyMonthlySumsHouse[month] / days
        hourlyMonthlySumsCommon[month] = hourlyMonthlySumsCommon[month] / days
        hourlyMonthlySumsTimeDiff[month] = hourlyMonthlySumsTimeDiff[month] / days

CostMiniSE3 = NoPTariff[NoPTariff['priceareas'] == 'SE3']
PTariffSE3 = PTariff[PTariff['priceareas'] == 'SE3']
TimeDiffSE3 = TimeDiff[TimeDiff['priceareas'] == 'SE3']
CommonSE3 = Collective[Collective['priceareas'] == 'SE3']

#create pivot tables for SE3
CostMiniSE3 = pd.pivot_table(CostMiniSE3, values='value', index='timestep', columns='trsp', aggfunc='sum')
PTariffSE3 = pd.pivot_table(PTariffSE3, values='value', index='timestep', columns='trsp', aggfunc='sum')
TimeDiffSE3 = pd.pivot_table(TimeDiffSE3, values='value', index='timestep', columns='trsp', aggfunc='sum')  
CommonSE3 = pd.pivot_table(CommonSE3, values='value', index='timestep', columns='trsp', aggfunc='sum')

#Add time references to the pivot tables

CostMiniSE3['HourOfYear'] = hourtime
PTariffSE3['HourOfYear'] = hourtime
TimeDiffSE3['HourOfYear'] = hourtime
CommonSE3['HourOfYear'] = hourtime

Priceareas = pd.unique(NoPTariff['priceareas'])

#print(CostMini.head())

# Normalize the data by dividing by the number of vehicles and price areas
hourlyMonthlySumsCostMini = hourlyMonthlySumsCostMini / (numberOfVehicles * numberOfPriceAreas)
hourlyMonthlySumsPTariff = hourlyMonthlySumsPTariff / (numberOfVehicles * numberOfPriceAreas)
hourlyMonthlySumsLogged = hourlyMonthlySumsLogged / (numberOfVehicles)
hourlyMonthlySumsCommon = hourlyMonthlySumsCommon / (numberOfVehicles * numberOfPriceAreas)  
hourlyMonthlySumsTimeDiff = hourlyMonthlySumsTimeDiff / (numberOfVehicles * numberOfPriceAreas)

# Find the global min and max values across both datasets to use for limits in color bar
min_value = min(hourlyMonthlySumsCostMini.values.min(), hourlyMonthlySumsPTariff.values.min(),hourlyMonthlySumsLogged.values.min(), hourlyMonthlySumsCommon.values.min(), hourlyMonthlySumsTimeDiff.values.min())
max_value = max(hourlyMonthlySumsCostMini.values.max(), hourlyMonthlySumsPTariff.values.max(),hourlyMonthlySumsLogged.values.max(), hourlyMonthlySumsCommon.values.max(), hourlyMonthlySumsTimeDiff.values.max())
caps=3
if HeatmapsCharging:
    plt.figure(figsize=(7, 5))
    sns.heatmap(hourlyMonthlySumsCostMini, cmap=CMAP, annot=False, 
                linewidths=.5, cbar_kws={'label': 'Charging [kWh/h]'},
                vmin=min_value, vmax=max_value)
    plt.title('(b) No tariff', fontsize=16)
    plt.xlabel('Month', fontsize=14)
    plt.ylabel('Hour of Day', fontsize=14)
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"Hourly_monthly_charging_heatmap_costmini.png", dpi=300)

    plt.figure(figsize=(7, 5))
    sns.heatmap(hourlyMonthlySumsPTariff, cmap=CMAP, annot=False, 
                linewidths=.5, cbar_kws={'label': 'Charging  [kWh/h]'},
                vmin=min_value, vmax=max_value)
    plt.title('(d) All hours tariff', fontsize=16)
    plt.xlabel('Month', fontsize=14)
    plt.ylabel('Hour of Day', fontsize=14)
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"Hourly_monthly_charging_heatmap_PTariff.png", dpi=300)

    plt.figure(figsize=(7, 5))
    sns.heatmap(hourlyMonthlySumsLogged, cmap=CMAP, annot=False,  
                linewidths=.5, cbar_kws={'label': 'Charging [kWh/h]'},
                vmin=min_value, vmax=max_value)         
    plt.title('(a) Logged charging', fontsize=16)
    plt.xlabel('Month', fontsize=14)
    plt.ylabel('Hour of Day', fontsize=14)
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"Hourly_monthly_charging_heatmap_logged.png", dpi=300)

    plt.figure(figsize=(7, 5))
    sns.heatmap(hourlyMonthlySumsCommon, cmap=CMAP, annot=False,
                linewidths=.5, cbar_kws={'label': 'Charging [kWh/h]'},
                vmin=min_value, vmax=max_value)
    plt.title('(e) Collective tariff', fontsize=16)
    plt.xlabel('Month', fontsize=14)
    plt.ylabel('Hour of Day', fontsize=14)
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"Hourly_monthly_charging_heatmap_common.png", dpi=300)

    plt.figure(figsize=(7, 5))
    sns.heatmap(hourlyMonthlySumsTimeDiff, cmap=CMAP, annot=False,
                linewidths=.5, cbar_kws={'label': 'Charging [kWh/h]'},
                vmin=min_value, vmax=max_value)
    plt.title('(c) Daytime tariff', fontsize=16)
    plt.xlabel('Month', fontsize=14)
    plt.ylabel('Hour of Day', fontsize=14)
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"Hourly_monthly_charging_heatmap_time_diff.png", dpi=300)

# Calculate percentage of charging by hour of day for logged charging
hourly_logged_charging_sum = dfTimestepSums.groupby('HourOfDay')['LoggedCharging'].sum()
total_charging = hourly_logged_charging_sum.sum()
hourly_charging_percentage = (hourly_logged_charging_sum / total_charging) * 100

# Create a bar graph for hourly charging distribution
plt.figure(figsize=(7, 5))
plt.bar(hourly_charging_percentage.index, 
        hourly_charging_percentage.values, 
        color=LOGGED_COLOR, 
        alpha=alpha_bars, 
        width=0.8)

plt.title('Distribution of Logged Charging by Hour of Day', fontsize=16)
plt.xlabel('Hour of Day', fontsize=14)
plt.ylabel('Percentage of Total Charging [%]', fontsize=14)
plt.xticks(range(1, 25))  # Set x-ticks to show all 24 hours

plt.savefig(f"hourly_percentage_logged_charging.png", dpi=300)

if StackedBars:
    # Calculate percentage of total load (household + charging) by hour of day
    hourly_household_sum = dfTimestepSums.groupby('HourOfDay')['HouseholdDemand'].sum()
    hourly_logged_charging_sum = dfTimestepSums.groupby('HourOfDay')['LoggedCharging'].sum() / numberOfVehicles  # Averaged per vehicle
    combined_load = dfTimestepSums['HouseholdDemand'] + (dfTimestepSums['LoggedCharging'] / numberOfVehicles)
    dfTimestepSums['CombinedLoad_logged'] = combined_load
    hourly_combined_sum_logged = dfTimestepSums.groupby('HourOfDay')['CombinedLoad_logged'].sum()

    total_combined_logged = hourly_combined_sum_logged.sum()
    hourly_combined_percentage_logged = (hourly_combined_sum_logged / total_combined_logged) * 100

    hourly_costmini_sum = dfTimestepSums.groupby('HourOfDay')['CostMiniCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)  # Averaged per vehicle and price area
    combinedload_costmini = dfTimestepSums['HouseholdDemand'] + (dfTimestepSums['CostMiniCharging'] / (numberOfVehicles * numberOfPriceAreas))
    dfTimestepSums['CombinedLoad_CostMini'] = combinedload_costmini
    hourly_combined_sum_costmini = dfTimestepSums.groupby('HourOfDay')['CombinedLoad_CostMini'].sum()
    total_combined_costmini = hourly_combined_sum_costmini.sum().sum()
    hourly_costmini_percentage = (hourly_costmini_sum / total_combined_costmini) * 100

    hourly_costmini_P_sum = dfTimestepSums.groupby('HourOfDay')['CostMiniPTariffCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)  # Averaged per vehicle and price area
    combinedload_costmini_P = dfTimestepSums['HouseholdDemand'] + (dfTimestepSums['CostMiniPTariffCharging'] / (numberOfVehicles * numberOfPriceAreas))
    dfTimestepSums['CombinedLoad_CostMini_P'] = combinedload_costmini_P 
    hourly_combined_sum_costmini_P = dfTimestepSums.groupby('HourOfDay')['CombinedLoad_CostMini_P'].sum()
    total_combined_costmini_P = hourly_combined_sum_costmini_P.sum()
    hourly_costmini_P_percentage = (hourly_costmini_P_sum / total_combined_costmini_P) * 100

    hourly_costmini_common_sum = dfTimestepSums.groupby('HourOfDay')['CostMiniCommonCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)  # Averaged per vehicle and price area
    combinedload_costmini_common = dfTimestepSums['HouseholdDemand'] + (dfTimestepSums['CostMiniCommonCharging'] / (numberOfVehicles * numberOfPriceAreas))
    dfTimestepSums['CombinedLoad_CostMini_Common'] = combinedload_costmini_common
    hourly_combined_sum_costmini_common = dfTimestepSums.groupby('HourOfDay')['CombinedLoad_CostMini_Common'].sum()
    total_combined_costmini_common = hourly_combined_sum_costmini_common.sum()
    hourly_costmini_common_percentage = (hourly_costmini_common_sum / total_combined_costmini_common) * 100

    hourly_timediff_sum = dfTimestepSums.groupby('HourOfDay')['TimeDiffCharging'].sum() / (numberOfVehicles * numberOfPriceAreas)  # Averaged per vehicle and price area
    combinedload_timediff = dfTimestepSums['HouseholdDemand'] + (dfTimestepSums['TimeDiffCharging'] / (numberOfVehicles * numberOfPriceAreas))
    dfTimestepSums['CombinedLoad_TimeDiff'] = combinedload_timediff
    hourly_combined_sum_timediff = dfTimestepSums.groupby('HourOfDay')['CombinedLoad_TimeDiff'].sum()
    total_combined_timediff = hourly_combined_sum_timediff.sum()
    hourly_timediff_percentage = (hourly_timediff_sum / total_combined_timediff) * 100

    # Create a stacked bar graph for hourly distribution
    plt.figure(figsize=(7, 5))

    # Plot household demand first (bottom of stack)
    plt.bar(hourly_household_sum.index, 
            (hourly_household_sum / total_combined_logged) * 100, 
            color=COLORS[3], 
            alpha=alpha_bars, 
            width=0.8,
            label='Household Demand')

    # Plot charging on top
    plt.bar(hourly_logged_charging_sum.index, 
            (hourly_logged_charging_sum / total_combined_logged) * 100, 
            color=LOGGED_COLOR, 
            alpha=alpha_bars, 
            width=0.8,
            bottom=(hourly_household_sum / total_combined_logged) * 100,
            label='EV Charging')

    plt.title('(a) Logged charging', fontsize=16)
    plt.xlabel('Hour of Day', fontsize=14)
    plt.ylabel('Percentage of Total Load [%]', fontsize=14)
    plt.ylim(0, 6)  # Set y-axis limit to 0-5.5%
    plt.xticks(range(1, 25))  # Set x-ticks to show all 24 hours
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.legend(fontsize=12, loc='lower left')
    plt.tight_layout()


    # Save the figure
    plt.savefig(f"hourly_percentage_combined_load.png", dpi=300)

    # Create stacked bar graph for Cost Minimized Charging with Household Demand
    plt.figure(figsize=(7, 5))
    # Plot household demand first (bottom of stack)
    plt.bar(hourly_household_sum.index, 
            (hourly_household_sum / total_combined_costmini) * 100, color=COLORS[3], alpha=alpha_bars, width=0.8, label='Household Demand')
    # Plot Cost Minimized Charging on top
    plt.bar(hourly_costmini_sum.index, 
            (hourly_costmini_sum / total_combined_costmini) * 100, color=LOGGED_COLOR, alpha=alpha_bars, width=0.8,
            bottom=(hourly_household_sum / total_combined_costmini) * 100, label='EV Charging')
    plt.title('(b) No tariff', fontsize=16)
    plt.xlabel('Hour of Day', fontsize=14)
    plt.ylabel('Percentage of Total Load [%]', fontsize=14)
    plt.ylim(0, 6)  # Set y-axis limit to 0-6%
    plt.xticks(range(1, 25))  # Set x-ticks to show all
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.legend(fontsize=12, loc='lower left')
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"hourly_percentage_combined_load_costmini.png", dpi=300)

    # Create stacked bar graph for Cost Minimized Charging with Power Tariff and Household Demand
    plt.figure(figsize=(7, 5)) 
    # Plot household demand first (bottom of stack)
    plt.bar(hourly_household_sum.index, 
            (hourly_household_sum / total_combined_costmini_P) * 100, color=COLORS[3], alpha=alpha_bars, width=0.8, label='Household Demand')
    # Plot Cost Minimized Charging with Power Tariff on top
    plt.bar(hourly_costmini_P_sum.index, 
            (hourly_costmini_P_sum / total_combined_costmini_P) * 100, color=LOGGED_COLOR, alpha=alpha_bars, width=0.8,
            bottom=(hourly_household_sum / total_combined_costmini_P) * 100, label='EV Charging')
    plt.title('(d) All hours tariff', fontsize=16)
    plt.xlabel('Hour of Day', fontsize=14)
    plt.ylabel('Percentage of Total Load [%]', fontsize=14)
    plt.ylim(0, 6)  # Set y-axis limit to 0-6%
    plt.xticks(range(1, 25))  # Set x-ticks to show all
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.legend(fontsize=12, loc='lower left')
    plt.tight_layout()

    # Save the figure
    plt.savefig(f"hourly_percentage_combined_load_costmini_PTariff.png", dpi=300)
    # Create stacked bar graph for Collective Tariff and Household Demand
    plt.figure(figsize=(7, 5))
    # Plot household demand first (bottom of stack)
    plt.bar(hourly_household_sum.index, 
            (hourly_household_sum / total_combined_costmini_common) * 100, color=COLORS[3], alpha=alpha_bars, width=0.8, label='Household Demand')
    # Plot Collective Tariff Charging on top
    plt.bar(hourly_costmini_common_sum.index, 
            (hourly_costmini_common_sum / total_combined_costmini_common) * 100, color=LOGGED_COLOR, alpha=alpha_bars, width=0.8,
            bottom=(hourly_household_sum / total_combined_costmini_common) * 100, label='EV Charging')
    plt.title('(e) Collective tariff', fontsize=16)
    plt.xlabel('Hour of Day', fontsize=14)
    plt.ylabel('Percentage of Total Load [%]', fontsize=14)
    plt.ylim(0, 6)  # Set y-axis limit to 0-6%
    plt.xticks(range(1, 25))  # Set x-ticks to show all
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.legend(fontsize=12, loc='lower left')
    plt.tight_layout()
    # Save the figure
    plt.savefig(f"hourly_percentage_combined_load_common.png", dpi=300)

    # Create stacked bar graph for Time-Differentiated Tariff and Household Demand
    plt.figure(figsize=(7, 5))
    # Plot household demand first (bottom of stack)
    plt.bar(hourly_household_sum.index, 
            (hourly_household_sum / total_combined_timediff) * 100, color=COLORS[3], alpha=alpha_bars, width=0.8, label='Household Demand')
    # Plot Time-Differentiated Tariff Charging on top
    plt.bar(hourly_timediff_sum.index, 
            (hourly_timediff_sum / total_combined_timediff) * 100, color=LOGGED_COLOR, alpha=alpha_bars, width=0.8,
            bottom=(hourly_household_sum / total_combined_timediff) * 100, label='EV Charging')
    plt.title('(c) Daytime tariff', fontsize=16)
    plt.xlabel('Hour of Day', fontsize=14)
    plt.ylabel('Percentage of Total Load [%]', fontsize=14)
    plt.ylim(0, 6)  # Set y-axis limit to 0-6%
    plt.xticks(range(1, 25))  # Set x-ticks to show all
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.legend(fontsize=12, loc='lower left')
    plt.tight_layout()
    # Save the figure
    plt.savefig(f"hourly_percentage_combined_load_timediff.png", dpi=300)

# Create a new variable for the combined load with household demand
CostminiWithHouse = hourlyMonthlySumsCostMini + hourlyMonthlySumsHouse
CostminiPTariffWithHouse = hourlyMonthlySumsPTariff + hourlyMonthlySumsHouse
LoggedChargingWithHouse = hourlyMonthlySumsLogged + hourlyMonthlySumsHouse
CostminiCommonwithHouse = hourlyMonthlySumsCommon + hourlyMonthlySumsHouse
CostminiTimeDiffwithHouse = hourlyMonthlySumsTimeDiff + hourlyMonthlySumsHouse
min_value = min(CostminiWithHouse.values.min(), CostminiPTariffWithHouse.values.min(),LoggedChargingWithHouse.values.min(), CostminiCommonwithHouse.values.min(), CostminiTimeDiffwithHouse.values.min())
max_value = max(CostminiWithHouse.values.max(), CostminiPTariffWithHouse.values.max(),LoggedChargingWithHouse.values.max(), CostminiCommonwithHouse.values.max(), CostminiTimeDiffwithHouse.values.max())

max_value_Logged_HH = LoggedChargingWithHouse.values.max()
max_value_CostMini_HH = CostminiWithHouse.values.max()
max_value_CostMiniPTariff_HH = CostminiPTariffWithHouse.values.max()
max_value_Common_HH = CostminiCommonwithHouse.values.max()
max_value_TimeDiff_HH = CostminiTimeDiffwithHouse.values.max()

max_value_Logged = hourlyMonthlySumsLogged.values.max()
max_value_CostMini = hourlyMonthlySumsCostMini.values.max()
max_value_CostMiniPTariff = hourlyMonthlySumsPTariff.values.max()
max_value_Common = hourlyMonthlySumsCommon.values.max()
max_value_TimeDiff = hourlyMonthlySumsTimeDiff.values.max()

print('Max values with household demand. Logged charging :', max_value_Logged_HH, 'kWh/h', 'CostMini:', max_value_CostMini_HH, 'kWh/h', 'CostMiniPTariff:', max_value_CostMiniPTariff_HH, 'kWh/h', 'Common:', max_value_Common_HH, 'kWh/h', 'TimeDiff:', max_value_TimeDiff_HH, 'kWh/h')
print('Max values only charging. Logged charging :', max_value_Logged, 'kWh/h', 'CostMini:', max_value_CostMini, 'kWh/h', 'CostMiniPTariff:', max_value_CostMiniPTariff, 'kWh/h', 'Common:', max_value_Common, 'kWh/h', 'TimeDiff:', max_value_TimeDiff, 'kWh/h')
plt.figure(figsize=(7, 5))
sns.heatmap(hourlyMonthlySumsCostMini+hourlyMonthlySumsHouse, cmap=CMAP, annot=False, 
            linewidths=.5, cbar_kws={'label': 'Load [kWh/h]'},
            vmin=min_value, vmax=max_value)
plt.title('(b) No tariff', fontsize=16)
plt.xlabel('Month', fontsize=14)
plt.ylabel('Hour of Day', fontsize=14)
plt.tight_layout()

# Save the figure
plt.savefig("Hourly_monthly_house+charging_heatmap_costmini.png", dpi=300)

plt.figure(figsize=(7, 5))
sns.heatmap(hourlyMonthlySumsPTariff+hourlyMonthlySumsHouse, cmap=CMAP, annot=False, 
            linewidths=.5, cbar_kws={'label': 'Load [kWh/h]'},
            vmin=min_value, vmax=max_value)
plt.title('(d) All hours tariff', fontsize=16)
plt.xlabel('Month', fontsize=14)
plt.ylabel('Hour of Day', fontsize=14)
plt.tight_layout()

# Save the figure
plt.savefig("Hourly_monthly_house+charging_heatmap_PTariff.png", dpi=300)

plt.figure(figsize=(7, 5))
sns.heatmap(hourlyMonthlySumsLogged+hourlyMonthlySumsHouse, cmap=CMAP, annot=False,
            linewidths=.5, cbar_kws={'label': 'Load [kWh/h]'},
            vmin=min_value, vmax=max_value)         
plt.title('(a) Logged charging', fontsize=16)
plt.xlabel('Month', fontsize=14)
plt.ylabel('Hour of Day', fontsize=14)
plt.tight_layout()

# Save the figure
plt.savefig("Hourly_monthly_house+charging_heatmap_logged.png", dpi=300)

plt.figure(figsize=(7, 5))
sns.heatmap(hourlyMonthlySumsCommon+hourlyMonthlySumsHouse, cmap=CMAP, annot=False,
            linewidths=.5, cbar_kws={'label': 'Load [kWh/h]'},
            vmin=min_value, vmax=max_value)
plt.title('(e) Collective tariff', fontsize=16)
plt.xlabel('Month', fontsize=14)
plt.ylabel('Hour of Day', fontsize=14)
plt.tight_layout()
# Save the figure
plt.savefig("Hourly_monthly_house+charging_heatmap_common.png", dpi=300)

plt.figure(figsize=(7, 5))
sns.heatmap(hourlyMonthlySumsTimeDiff+hourlyMonthlySumsHouse, cmap=CMAP, annot=False,
            linewidths=.5, cbar_kws={'label': 'Load [kWh/h]'},
            vmin=min_value, vmax=max_value)
plt.title('(c) Daytime tariff', fontsize=16)
plt.xlabel('Month', fontsize=14)
plt.ylabel('Hour of Day', fontsize=14)
plt.tight_layout()
# Save the figure
plt.savefig("Hourly_monthly_house+charging_heatmap_time_diff.png", dpi=300)

print('Values in heatmaps', hourlyMonthlySumsCostMini.sum().sum(), hourlyMonthlySumsPTariff.sum().sum(), hourlyMonthlySumsLogged.sum().sum(), hourlyMonthlySumsCommon.sum().sum(), hourlyMonthlySumsTimeDiff.sum().sum())
print('Values in heatmaps with household demand', CostminiWithHouse.sum().sum(), CostminiPTariffWithHouse.sum().sum(), LoggedChargingWithHouse.sum().sum(), CostminiCommonwithHouse.sum().sum(), CostminiTimeDiffwithHouse.sum().sum())
print('Maximum value in heatmaps with household demand', 'Logged',max_value_Logged_HH,'Costmini', max_value_CostMini_HH,'CostMiniPTariff', max_value_CostMiniPTariff_HH, 'Common', max_value_Common_HH, 'TimeDiff', max_value_TimeDiff_HH)
print('Maximum value in heatmaps only charging', 'Logged',max_value_Logged,'Costmini', max_value_CostMini,'CostMiniPTariff', max_value_CostMiniPTariff, 'Common', max_value_Common, 'TimeDiff', max_value_TimeDiff)
print('Average value in heatmaps with household demand', 'Logged',LoggedChargingWithHouse.values.mean(),'Costmini', CostminiWithHouse.values.mean(),'CostMiniPTariff', CostminiPTariffWithHouse.values.mean(), 'Common', CostminiCommonwithHouse.values.mean(), 'TimeDiff', CostminiTimeDiffwithHouse.values.mean())
print('Average value in heatmaps only charging', 'Logged',hourlyMonthlySumsLogged.values.mean(),'Costmini', hourlyMonthlySumsCostMini.values.mean(),'CostMiniPTariff', hourlyMonthlySumsPTariff.values.mean(), 'Common', hourlyMonthlySumsCommon.values.mean(), 'TimeDiff', hourlyMonthlySumsTimeDiff.values.mean())
# Scatter plots of charging vs electricity price
#ymax = max(hourOfYearLogged.max(), hourOfYearCostMini.max(), hourOfYearPTariff.max(), hourOfYearCommon.max())
#ymin = min(hourOfYearLogged.min(), hourOfYearCostMini.min(), hourOfYearPTariff.min(), hourOfYearCommon.min())
ymax = max(hourOfYearLogged.max(), hourOfYearCostMini.max(), hourOfYearPTariff.max(), hourOfYearCommon.max(), hourOfYearTimeDiff.max())
ymin = min(hourOfYearLogged.min(), hourOfYearCostMini.min(), hourOfYearPTariff.min(), hourOfYearCommon.min(), hourOfYearTimeDiff.min())

print('Max charging in scatter plots. Logged:', hourOfYearLogged.max(), 'kWh/h', 'CostMini:', hourOfYearCostMini.max(), 'kWh/h', 'CostMiniPTariff:', hourOfYearPTariff.max(), 'kWh/h, Common:', hourOfYearCommon.max(), 'kWh/h', 'TimeDiff:', hourOfYearTimeDiff.max(), 'kWh/h')
print('Average charging in scatter plots. Logged:', hourOfYearLogged.mean(), 'kWh/h', 'CostMini:', hourOfYearCostMini.mean(), 'kWh/h', 'CostMiniPTariff:', hourOfYearPTariff.mean(), 'kWh/h, Common:', hourOfYearCommon.mean(), 'kWh/h', 'TimeDiff:', hourOfYearTimeDiff.mean(), 'kWh/h')

if ScatterEprice:
    plt.figure(figsize=(7, 5))
    plt.scatter(Eprices['SE3 Price (EUR)']/1000, hourOfYearLogged, color=LOGGED_COLOR, alpha=alpha_scatters)
    plt.title('(a) Logged charging', fontsize=16)
    plt.xlabel('Electricity Price [€/kWh]', fontsize=14)
    plt.ylabel('Charging [kWh/h]', fontsize=14)
    plt.ylim(ymin, ymax*1.1)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.tight_layout()
    # Save the figure
    plt.savefig("Logged_charging_vs_price.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.scatter(Eprices['SE3 Price (EUR)']/1000, hourOfYearCostMini, color=LOGGED_COLOR, alpha=alpha_scatters)
    plt.title('(b) No tariff', fontsize=16)
    plt.xlabel('Electricity Price [€/kWh]', fontsize=14)
    plt.ylabel('Charging [kWh/h]', fontsize=14)
    plt.ylim(ymin, ymax*1.1)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.tight_layout()
    # Save the figure
    plt.savefig("CostMini_charging_vs_price.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.scatter(Eprices['SE3 Price (EUR)']/1000, hourOfYearPTariff, color=LOGGED_COLOR, alpha=alpha_scatters)
    plt.title('(d) All hours tariff', fontsize=16)
    plt.xlabel('Electricity Price [€/kWh]', fontsize=14)
    plt.ylabel('Charging [kWh/h]', fontsize=14)
    plt.ylim(ymin, ymax*1.1)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.tight_layout()
    # Save the figure
    plt.savefig("CostMini_PTariff_charging_vs_price.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.scatter(Eprices['SE3 Price (EUR)']/1000, hourOfYearCommon, color=LOGGED_COLOR, alpha=alpha_scatters)
    plt.title('(e) Collective tariff', fontsize=16)
    plt.xlabel('Electricity Price [€/kWh]', fontsize=14)
    plt.ylabel('Charging [kWh/h]', fontsize=14)
    plt.ylim(ymin, ymax*1.1)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.tight_layout()
    # Save the figure
    plt.savefig("CostMini_PTariff_collective_charging_vs_price.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.scatter(Eprices['SE3 Price (EUR)']/1000, hourOfYearTimeDiff, color=LOGGED_COLOR, alpha=alpha_scatters)
    plt.title('(c) Daytime tariff', fontsize=16)
    plt.xlabel('Electricity Price [€/kWh]', fontsize=14)
    plt.ylabel('Charging [kWh/h]', fontsize=14)
    plt.ylim(ymin, ymax*1.1)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.tight_layout()
    # Save the figure
    plt.savefig("CostMini_PTariff_time_diff_charging_vs_price.png", dpi=300)


if PerEpriceareaSE3Only:
    # calculate cost of charging per vehicle for only SE3 price area without yeartime and hourofyear columns
    HourlyChargingCostMini_SE3 = CostMiniSE3.copy()  # Create a copy to avoid modifying original
    vehicle_columns = [col for col in CostMiniSE3.columns if col != 'HourOfYear']  # Get vehicle columns
    HourlyChargingCostMini_SE3 = CostMiniSE3.groupby('HourOfYear')[vehicle_columns].sum()
    HourlyChargingPTariff_SE3 = PTariffSE3.copy()  # Create a copy to avoid modifying original
    HourlyChargingPTariff_SE3 = PTariffSE3.groupby('HourOfYear')[vehicle_columns].sum()
    HourlyChargingCommon_SE3 = CommonSE3.copy()  # Create a copy to avoid modifying original
    HourlyChargingCommon_SE3 = CommonSE3.groupby('HourOfYear')[vehicle_columns].sum()
    HourlyChargingTimeDiff_SE3 = TimeDiffSE3.copy()  # Create a copy to avoid modifying original
    HourlyChargingTimeDiff_SE3 = TimeDiffSE3.groupby('HourOfYear')[vehicle_columns].sum()
    #print('Hourly charging for SE3 price area - No Tariff (first 5 rows):')
    #print(HourlyChargingCostMini_SE3.head())
    #print('Eprices for SE3 price area (first 5 rows):' )
    Epricenew = Eprices['SE3 Price (EUR)'].values[:, np.newaxis]
    #print(Epricenew)
    CostOfChargingPerVehicle_CostMini_SE3 = HourlyChargingCostMini_SE3*Eprices['SE3 Price (EUR)'].values[:, np.newaxis] / 1000  # Convert EUR/MWh to EUR/kWh - unit = €
    CostOfChargingPerVehicle_PTariff_SE3 = HourlyChargingPTariff_SE3*Eprices['SE3 Price (EUR)'].values[:, np.newaxis] / 1000  # Convert EUR/MWh to EUR/kWh - unit = €
    CostOfChargingPerVehicle_Common_SE3 = HourlyChargingCommon_SE3*Eprices['SE3 Price (EUR)'].values[:, np.newaxis] / 1000  # Convert EUR/MWh to EUR/kWh - unit = €
    CostOfChargingPerVehicle_TimeDiff_SE3 = HourlyChargingTimeDiff_SE3*Eprices['SE3 Price (EUR)'].values[:, np.newaxis] / 1000  # Convert EUR/MWh to EUR/kWh - unit = €
    #print('Cost of charging per vehicle for SE3 price area - No Tariff shape:')
    #print(CostOfChargingPerVehicle_CostMini_SE3.shape)
    TotalCostOfCharging_perVehicle_CostMini_SE3 = CostOfChargingPerVehicle_CostMini_SE3.sum(axis=0)
    TotalCostOfCharging_perVehicle_PTariff_SE3 = CostOfChargingPerVehicle_PTariff_SE3.sum(axis=0)
    TotalCostOfCharging_perVehicle_Common_SE3 = CostOfChargingPerVehicle_Common_SE3.sum(axis=0)
    TotalCostOfCharging_perVehicle_TimeDiff_SE3 = CostOfChargingPerVehicle_TimeDiff_SE3.sum(axis=0)
    #print('Total cost of charging per vehicle for SE3 price area - No Tariff shape:', TotalCostOfCharging_perVehicle_CostMini_SE3.shape)

    mean_totalcost_CostMini_SE3 = TotalCostOfCharging_perVehicle_CostMini_SE3.mean()
    mean_totalcost_PTariff_SE3 = TotalCostOfCharging_perVehicle_PTariff_SE3.mean()
    mean_totalcost_Common_SE3 = TotalCostOfCharging_perVehicle_Common_SE3.mean()
    mean_totalcost_TimeDiff_SE3 = TotalCostOfCharging_perVehicle_TimeDiff_SE3.mean()

    plt.figure(figsize=(7, 5))
    plt.hist(TotalCostOfCharging_perVehicle_CostMini_SE3.values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
    plt.axvline(mean_totalcost_CostMini_SE3, color='black', linestyle='dashed', linewidth=1)
    plt.title('(a) No tariff (SE3)', fontsize=16)
    plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
    plt.ylabel('Frequency', fontsize=14)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.xlim(0, TotalCostOfCharging_perVehicle_PTariff_SE3.values.flatten().max()*1.1)
    plt.tight_layout()
    # Save the figure
    plt.savefig("Cost_of_charging_per_vehicle_no_tariff_SE3_histogram.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.hist(TotalCostOfCharging_perVehicle_PTariff_SE3.values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
    plt.axvline(mean_totalcost_PTariff_SE3, color='black', linestyle='dashed', linewidth=1)
    plt.title('(c) All Hours tariff (SE3)', fontsize=16)
    plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
    plt.ylabel('Frequency', fontsize=14)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.xlim(0, TotalCostOfCharging_perVehicle_PTariff_SE3.values.flatten().max()*1.1)
    plt.tight_layout()
    # Save the figure
    plt.savefig("Cost_of_charging_per_vehicle_all_hours_tariff_SE3_histogram.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.hist(TotalCostOfCharging_perVehicle_Common_SE3.values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
    plt.axvline(mean_totalcost_Common_SE3, color='black', linestyle='dashed', linewidth=1)
    plt.title('(d) Collective tariff (SE3)', fontsize=16)
    plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
    plt.ylabel('Frequency', fontsize=14)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.xlim(0, TotalCostOfCharging_perVehicle_PTariff_SE3.values.flatten().max()*1.1)
    plt.tight_layout()
    # Save the figure
    plt.savefig("Cost_of_charging_per_vehicle_collective_tariff_SE3_histogram.png", dpi=300)

    plt.figure(figsize=(7, 5))
    plt.hist(TotalCostOfCharging_perVehicle_TimeDiff_SE3.values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
    plt.axvline(mean_totalcost_TimeDiff_SE3, color='black', linestyle='dashed', linewidth=1)
    plt.title('(b) Daytime tariff (SE3)', fontsize=16)
    plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
    plt.ylabel('Frequency', fontsize=14)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.xlim(0, TotalCostOfCharging_perVehicle_PTariff_SE3.values.flatten().max()*1.1)
    plt.tight_layout()
    # Save the figure
    plt.savefig("Cost_of_charging_per_vehicle_daytime_tariff_SE3_histogram.png", dpi=300)

    IncreaseInCost_Allhours=(TotalCostOfCharging_perVehicle_PTariff_SE3 - TotalCostOfCharging_perVehicle_CostMini_SE3) / TotalCostOfCharging_perVehicle_CostMini_SE3.abs() * 100
    IncreaseInCost_Collective=(TotalCostOfCharging_perVehicle_Common_SE3 - TotalCostOfCharging_perVehicle_CostMini_SE3) / TotalCostOfCharging_perVehicle_CostMini_SE3.abs() * 100
    IncreaseInCost_Daytime=(TotalCostOfCharging_perVehicle_TimeDiff_SE3 - TotalCostOfCharging_perVehicle_CostMini_SE3) / TotalCostOfCharging_perVehicle_CostMini_SE3.abs() * 100


if PerEpricearea:
    # Create dictionaries to store data for each price area
    HourlyCharging = {}
    CostOfChargingPerVehicle = {}
    TotalCostOfCharging_perVehicle = {}
    IncreaseInCostPercent = {
        'All hours': {},
        'Collective': {},
        'Daytime': {}
    }

    IncreaseInCost = {
        'All hours': {},
        'Collective': {},
        'Daytime': {}
    }

    avg_allhours_percent = {}
    avg_collective_percent = {}
    avg_daytime_percent = {}
    median_allhours_percent = {}
    median_collective_percent = {}
    median_daytime_percent = {}

    avg_allhours = {}
    avg_collective = {}
    avg_daytime = {}
    median_allhours = {}
    median_collective = {}
    median_daytime = {}

    std_allhours = {}
    std_collective = {}
    std_daytime = {}

    avg_cost_no_tariff = {}
    std_cost_no_tariff = {}
    avg_cost_allhours = {}
    std_cost_allhours = {}
    avg_cost_collective = {}
    std_cost_collective = {}
    avg_cost_daytime = {}
    std_cost_daytime = {}
    Cost_ofCharging_per_vehicle_and_kWh = {}
    avg_cost_kWh_no_tariff = {}
    avg_cost_kWh_allhours = {}
    avg_cost_kWh_collective = {}
    avg_cost_kWh_daytime = {}
    std_notariff_kWh = {}
    std_allhours_kWh = {}
    std_collective_kWh = {}    
    std_daytime_kWh = {}


    Cost_ofCharging_pervehicle_summary = pd.DataFrame()

    # Process each price area
    for price_area in Priceareas:
        print(f"\nProcessing price area: {price_area}")
        
        # Filter data for this price area
        CostMini_area = NoPTariff[NoPTariff['priceareas'] == price_area]
        PTariff_area = PTariff[PTariff['priceareas'] == price_area]
        TimeDiff_area = TimeDiff[TimeDiff['priceareas'] == price_area]
        Common_area = Collective[Collective['priceareas'] == price_area]
        
        # Create pivot tables
        CostMini_area = pd.pivot_table(CostMini_area, values='value', index='timestep', columns='trsp', aggfunc='sum')
        PTariff_area = pd.pivot_table(PTariff_area, values='value', index='timestep', columns='trsp', aggfunc='sum')
        TimeDiff_area = pd.pivot_table(TimeDiff_area, values='value', index='timestep', columns='trsp', aggfunc='sum')  
        Common_area = pd.pivot_table(Common_area, values='value', index='timestep', columns='trsp', aggfunc='sum')
        
        # Add time references
        CostMini_area['HourOfYear'] = hourtime
        PTariff_area['HourOfYear'] = hourtime
        TimeDiff_area['HourOfYear'] = hourtime
        Common_area['HourOfYear'] = hourtime
        
        # Store hourly charging data for this area
        vehicle_columns = [col for col in CostMini_area.columns if col != 'HourOfYear']
        
        # Group by HourOfYear to get hourly charging per vehicle
        HourlyCharging[f'CostMini_{price_area}'] = CostMini_area.groupby('HourOfYear')[vehicle_columns].sum()
        HourlyCharging[f'PTariff_{price_area}'] = PTariff_area.groupby('HourOfYear')[vehicle_columns].sum()
        HourlyCharging[f'Common_{price_area}'] = Common_area.groupby('HourOfYear')[vehicle_columns].sum()
        HourlyCharging[f'TimeDiff_{price_area}'] = TimeDiff_area.groupby('HourOfYear')[vehicle_columns].sum()
        
        # Calculate cost by multiplying hourly charging by corresponding price area's electricity prices
        price_column = f'{price_area} Price (EUR)'
        if price_column in Eprices.columns:
            print(f"Using price data from column: {price_column}")
            area_prices = Eprices[price_column].values[:, np.newaxis]
            
            # Calculate costs
            CostOfChargingPerVehicle[f'CostMini_{price_area}'] = HourlyCharging[f'CostMini_{price_area}'] * area_prices / 1000
            CostOfChargingPerVehicle[f'PTariff_{price_area}'] = HourlyCharging[f'PTariff_{price_area}'] * area_prices / 1000
            CostOfChargingPerVehicle[f'Common_{price_area}'] = HourlyCharging[f'Common_{price_area}'] * area_prices / 1000
            CostOfChargingPerVehicle[f'TimeDiff_{price_area}'] = HourlyCharging[f'TimeDiff_{price_area}'] * area_prices / 1000

            Cost_ofCharging_per_vehicle_and_kWh[f'CostMini_{price_area}'] = CostOfChargingPerVehicle[f'CostMini_{price_area}'].sum(axis=0) / DemandPerVehicle
            Cost_ofCharging_per_vehicle_and_kWh[f'PTariff_{price_area}'] = CostOfChargingPerVehicle[f'PTariff_{price_area}'].sum(axis=0) / DemandPerVehicle
            Cost_ofCharging_per_vehicle_and_kWh[f'Common_{price_area}'] = CostOfChargingPerVehicle[f'Common_{price_area}'].sum(axis=0) / DemandPerVehicle
            Cost_ofCharging_per_vehicle_and_kWh[f'TimeDiff_{price_area}'] = CostOfChargingPerVehicle[f'TimeDiff_{price_area}'].sum(axis=0) / DemandPerVehicle

            avg_cost_kWh_no_tariff[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'CostMini_{price_area}'].mean()
            avg_cost_kWh_allhours[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'PTariff_{price_area}'].mean()
            avg_cost_kWh_collective[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'Common_{price_area}'].mean()
            avg_cost_kWh_daytime[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'TimeDiff_{price_area}'].mean()
            std_notariff_kWh[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'CostMini_{price_area}'].std()
            std_allhours_kWh[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'PTariff_{price_area}'].std()
            std_collective_kWh[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'Common_{price_area}'].std()    
            std_daytime_kWh[price_area] = Cost_ofCharging_per_vehicle_and_kWh[f'TimeDiff_{price_area}'].std()

            # Sum costs over all hours to get total cost per vehicle
            TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'] = CostOfChargingPerVehicle[f'CostMini_{price_area}'].sum(axis=0)
            TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'] = CostOfChargingPerVehicle[f'PTariff_{price_area}'].sum(axis=0)
            TotalCostOfCharging_perVehicle[f'Common_{price_area}'] = CostOfChargingPerVehicle[f'Common_{price_area}'].sum(axis=0)
            TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'] = CostOfChargingPerVehicle[f'TimeDiff_{price_area}'].sum(axis=0)
            
            # Calculate percentage increase in cost
            base_cost = TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].abs()  # Using abs() to avoid division by zero issues
            print('Costofchargingshape',Cost_ofCharging_per_vehicle_and_kWh[f'CostMini_{price_area}'].shape)
            
            IncreaseInCostPercent['All hours'][price_area] = (TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'] - 
                                                      TotalCostOfCharging_perVehicle[f'CostMini_{price_area}']) / base_cost * 100
            IncreaseInCostPercent['Collective'][price_area] = (TotalCostOfCharging_perVehicle[f'Common_{price_area}'] - 
                                                   TotalCostOfCharging_perVehicle[f'CostMini_{price_area}']) / base_cost * 100
            IncreaseInCostPercent['Daytime'][price_area] = (TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'] - 
                                                   TotalCostOfCharging_perVehicle[f'CostMini_{price_area}']) / base_cost * 100
            
            IncreaseInCost['All hours'][price_area] = (TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'] - 
                                                      TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'])
            IncreaseInCost['Collective'][price_area] = (TotalCostOfCharging_perVehicle[f'Common_{price_area}'] - 
                                                   TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'])
            IncreaseInCost['Daytime'][price_area] = (TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'] - 
                                                   TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'])
            
            if PerEpricehists:

                # Create histograms
                xmax_value = max(TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].values.flatten().max(),
                                 TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].values.flatten().max(),
                                 TotalCostOfCharging_perVehicle[f'Common_{price_area}'].values.flatten().max(),
                                 TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].values.flatten().max()) * 1.1
                plt.figure(figsize=(7, 5))
                plt.hist(TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
                plt.axvline(TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].mean(), color='black', linestyle='dashed', linewidth=1)
                plt.title(f'(b) No tariff ({price_area})', fontsize=16)
                plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
                plt.ylabel('Frequency', fontsize=14)
                plt.grid(axis='y', linestyle='--', alpha=0.3)
                plt.xlim(-10, xmax_value)
                plt.ylim(0,32)
                plt.yticks(np.arange(0, 33, 5))
                plt.tight_layout()
                plt.savefig(f"Cost_of_charging_per_vehicle_no_tariff_{price_area}_histogram.png", dpi=300)

                plt.figure(figsize=(7, 5))
                plt.hist(TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
                plt.axvline(TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].mean(), color='black', linestyle='dashed', linewidth=1)
                plt.title(f'(d) All Hours tariff ({price_area})', fontsize=16)
                plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
                plt.grid(axis='y', linestyle='--', alpha=0.3)
                plt.ylabel('Frequency', fontsize=14)
                plt.xlim(-10, xmax_value)
                plt.yticks(np.arange(0, 33, 5))
                plt.ylim(0,32)
                plt.tight_layout()
                plt.savefig(f"Cost_of_charging_per_vehicle_all_hours_tariff_{price_area}_histogram.png", dpi=300)

                plt.figure(figsize=(7, 5))
                plt.hist(TotalCostOfCharging_perVehicle[f'Common_{price_area}'].values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
                plt.axvline(TotalCostOfCharging_perVehicle[f'Common_{price_area}'].mean(), color='black', linestyle='dashed', linewidth=1)
                plt.title(f'(e) Collective tariff ({price_area})', fontsize=16)
                plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
                plt.ylabel('Frequency', fontsize=14)
                plt.grid(axis='y', linestyle='--', alpha=0.3)
                plt.xlim(-10, xmax_value)
                plt.yticks(np.arange(0, 33, 5))
                plt.ylim(0,32)
                plt.tight_layout()
                plt.savefig(f"Cost_of_charging_per_vehicle_collective_tariff_{price_area}_histogram.png", dpi=300)

                plt.figure(figsize=(7, 5))
                plt.hist(TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
                plt.axvline(TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].mean(), color='black', linestyle='dashed', linewidth=1)
                plt.title(f'(c) Daytime tariff ({price_area})', fontsize=16)
                plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
                plt.ylabel('Frequency', fontsize=14)
                plt.grid(axis='y', linestyle='--', alpha=0.3)
                plt.yticks(np.arange(0, 33, 5))
                plt.ylim(0,32)
                plt.xlim(-10, xmax_value)
                plt.tight_layout()
                plt.savefig(f"Cost_of_charging_per_vehicle_daytime_tariff_{price_area}_histogram.png", dpi=300)

                print(f"The average cost of charging per vehicle in {price_area} without tariff is: {TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].mean():.2f} €")
                print(f"The average cost of charging per vehicle in {price_area} with all hours tariff is: {TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].mean():.2f} €")
                print(f"The average cost of charging per vehicle in {price_area} with collective tariff is: {TotalCostOfCharging_perVehicle[f'Common_{price_area}'].mean():.2f} €")
                print(f"The average cost of charging per vehicle in {price_area} with daytime tariff is: {TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].mean():.2f} €")

            # Print summary statistics
            base_total = TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].sum()
            allhours_total = TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].sum()
            collective_total = TotalCostOfCharging_perVehicle[f'Common_{price_area}'].sum()
            daytime_total = TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].sum()

            avg_allhours_percent[price_area] = (allhours_total - base_total) / abs(base_total) * 100
            avg_collective_percent[price_area] = (collective_total - base_total) / abs(base_total) * 100
            avg_daytime_percent[price_area] = (daytime_total - base_total) / abs(base_total) * 100

            print(f"\nSummary for {price_area}:")
            print(f"Overall cost increase - All hours: {avg_allhours_percent[price_area]:.2f}%")
            print(f"Overall cost increase - Daytime: {avg_daytime_percent[price_area]:.2f}%")
            print(f"Overall cost increase - Collective: {avg_collective_percent[price_area]:.2f}%")
            print(f"Median vehicle cost increase - All hours: {IncreaseInCostPercent['All hours'][price_area].median():.2f}%")
            print(f"Median vehicle cost increase - Daytime: {IncreaseInCostPercent['Daytime'][price_area].median():.2f}%")
            print(f"Median vehicle cost increase - Collective: {IncreaseInCostPercent['Collective'][price_area].median():.2f}%")

            median_allhours_percent[price_area] = IncreaseInCostPercent['All hours'][price_area].median()
            median_collective_percent[price_area] = IncreaseInCostPercent['Collective'][price_area].median()
            median_daytime_percent[price_area] = IncreaseInCostPercent['Daytime'][price_area].median()

            avg_allhours[price_area] = IncreaseInCost['All hours'][price_area].mean()
            avg_daytime[price_area] = IncreaseInCost['Daytime'][price_area].mean()
            avg_collective[price_area] = IncreaseInCost['Collective'][price_area].mean()
            median_allhours[price_area] = IncreaseInCost['All hours'][price_area].median()
            median_daytime[price_area] = IncreaseInCost['Daytime'][price_area].median()
            median_collective[price_area] = IncreaseInCost['Collective'][price_area].median()
            std_allhours[price_area] = IncreaseInCost['All hours'][price_area].std()
            std_daytime[price_area] = IncreaseInCost['Daytime'][price_area].std()
            std_collective[price_area] = IncreaseInCost['Collective'][price_area].std()

            avg_cost_no_tariff[price_area] = TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].mean()
            std_cost_no_tariff[price_area] = TotalCostOfCharging_perVehicle[f'CostMini_{price_area}'].std()
            avg_cost_allhours[price_area] = TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].mean()
            std_cost_allhours[price_area] = TotalCostOfCharging_perVehicle[f'PTariff_{price_area}'].std()
            avg_cost_collective[price_area] = TotalCostOfCharging_perVehicle[f'Common_{price_area}'].mean()
            std_cost_collective[price_area] = TotalCostOfCharging_perVehicle[f'Common_{price_area}'].std()
            avg_cost_daytime[price_area] = TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].mean()
            std_cost_daytime[price_area] = TotalCostOfCharging_perVehicle[f'TimeDiff_{price_area}'].std()

        else:
            print(f"Warning: Price column '{price_column}' not found in Eprices DataFrame")

    # Create a single logged-SE3 histogram 
    if PerEpricehists:
        try:
            LoggedHourly = LoggedCharging.groupby(hourtime).sum()
            se3_prices = Eprices['SE3 Price (EUR)'].values[:, np.newaxis]

            CostOfChargingPerVehicle_Logged_SE3 = LoggedHourly * se3_prices / 1000
            TotalCostOfCharging_perVehicle_Logged_SE3 = CostOfChargingPerVehicle_Logged_SE3.sum(axis=0)

            mean_totalcost_Logged_SE3 = TotalCostOfCharging_perVehicle_Logged_SE3.mean()
            xmax_value = TotalCostOfCharging_perVehicle_Logged_SE3.values.max() * 1.1

            plt.figure(figsize=(7, 5))
            plt.hist(TotalCostOfCharging_perVehicle_Logged_SE3.values.flatten(), bins=50, color=LOGGED_COLOR, alpha=alpha_hists)
            plt.axvline(mean_totalcost_Logged_SE3, color='black', linestyle='dashed', linewidth=1)
            plt.title('(a) Logged charging (SE3)', fontsize=16)
            plt.xlabel('Cost of Purchased Electricity [€]', fontsize=14)
            plt.ylabel('Frequency', fontsize=14)
            plt.grid(axis='y', linestyle='--', alpha=0.3)
            plt.xlim(-10, xmax_value)
            plt.tight_layout()
            plt.savefig('Cost_of_charging_per_vehicle_logged_SE3_histogram.png', dpi=300)
        except Exception:
            print('Warning: could not create logged SE3 histogram (missing LoggedCharging, hourtime, or Eprices)')

    # Create additional aggregated analysis across all price areas
    if len(Priceareas) > 1:
        # Combine data from all price areas for aggregated plots
        all_areas_increase_percent = {
            'All hours': pd.concat([IncreaseInCostPercent['All hours'][area] for area in Priceareas if area in IncreaseInCostPercent['All hours']]),
            'Collective': pd.concat([IncreaseInCostPercent['Collective'][area] for area in Priceareas if area in IncreaseInCostPercent['Collective']]),
            'Daytime': pd.concat([IncreaseInCostPercent['Daytime'][area] for area in Priceareas if area in IncreaseInCostPercent['Daytime']])
        }
        all_areas_increase = {
            'All hours': pd.concat([IncreaseInCost['All hours'][area] for area in Priceareas if area in IncreaseInCost['All hours']]),
            'Collective': pd.concat([IncreaseInCost['Collective'][area] for area in Priceareas if area in IncreaseInCost['Collective']]),
            'Daytime': pd.concat([IncreaseInCost['Daytime'][area] for area in Priceareas if area in IncreaseInCost['Daytime']])
        }

        summary_rows = []
        tariff_keys = {
            'No tariff': 'CostMini',
            'Daytime tariff': 'TimeDiff',
            'All hours tariff': 'PTariff',
            'Collective tariff': 'Common',
        }
        demand_threshold_kwh = 0.0 # adjust if needed to filter out low-demand vehicles for spread calculations
        use_filter_for_spread = True

        for price_area in sorted(Priceareas):
            for tariff_name, tariff_key in tariff_keys.items():
                cost_series = TotalCostOfCharging_perVehicle[f'{tariff_key}_{price_area}']
                demand_series = DemandPerVehicle.reindex(cost_series.index)

                joined = pd.DataFrame({
                    'cost_eur': cost_series,
                    'demand_kwh': demand_series,
                }).dropna()

                if use_filter_for_spread:
                    spread_df = joined[joined['demand_kwh'] >= demand_threshold_kwh].copy()
                else:
                    spread_df = joined.copy()

                if spread_df.empty:
                    raise ValueError(f'No vehicles left after demand filtering for {price_area} / {tariff_name}.')

                per_kwh = spread_df['cost_eur'] / spread_df['demand_kwh']
                weighted_mean = spread_df['cost_eur'].sum() / spread_df['demand_kwh'].sum()

                summary_rows.append({
                    'price_area': price_area,
                    'tariff': tariff_name,
                    'mean_cost_eur': joined['cost_eur'].mean(),
                    'filtered_mean_cost_eur': spread_df['cost_eur'].mean(),
                    'weighted_mean_eur_per_kwh': weighted_mean,
                    'mean_eur_per_kwh': per_kwh.mean(),
                    'median_eur_per_kwh': per_kwh.median(),
                    'std_eur_per_kwh': per_kwh.std(ddof=1),
                    'n_vehicles': int(spread_df.shape[0]),
                    'min_demand_kwh': float(spread_df['demand_kwh'].min()),
                    'max_demand_kwh': float(spread_df['demand_kwh'].max()),
                })

        summary_df = pd.DataFrame(summary_rows)

        print("\nMean annual cost per vehicle [€] (all vehicles):")
        print(summary_df.pivot(index='price_area', columns='tariff', values='mean_cost_eur'))

        print("\nMean annual cost per vehicle [€] after filtering out very low-demand vehicles:")
        print(summary_df.pivot(index='price_area', columns='tariff', values='filtered_mean_cost_eur'))

        print("\nDemand-weighted cost [€/kWh]:")
        print(summary_df.pivot(index='price_area', columns='tariff', values='weighted_mean_eur_per_kwh'))

        # Overall summary across price areas: average of the per-area percent increases vs no tariff
        if avg_allhours_percent:
            overall_avg_allhours_percent = np.mean(list(avg_allhours_percent.values()))
            overall_avg_collective_percent = np.mean(list(avg_collective_percent.values()))
            overall_avg_daytime_percent = np.mean(list(avg_daytime_percent.values()))

            print("\nAverage cost increase across price areas (vs no tariff):")
            print(f"All hours: {overall_avg_allhours_percent:.2f}%")
            print(f"Daytime: {overall_avg_daytime_percent:.2f}%")
            print(f"Collective: {overall_avg_collective_percent:.2f}%")

        price_areas = sorted(summary_df['price_area'].unique().tolist())
        tariffs = ['No tariff', 'Daytime tariff', 'All hours tariff', 'Collective tariff']
        x = np.arange(len(price_areas))
        width = 0.2
        offsets = [-1.5, -0.5, 0.5, 1.5]
        tariff_colors = {
            'No tariff': COLORS[0],
            'Daytime tariff': COLORS[2],
            'All hours tariff': COLORS[1],
            'Collective tariff': COLORS[3],
        }

        plt.figure(figsize=(7, 5))
        for tariff_name, offset in zip(tariffs, offsets):
            subset = summary_df[summary_df['tariff'] == tariff_name].set_index('price_area').reindex(price_areas)
            plt.bar(
                x + offset * width,
                subset['weighted_mean_eur_per_kwh'].values,
                width,
                label=tariff_name,
                color=tariff_colors[tariff_name],
                capsize=3,
                alpha=1.0,
            )

        plt.ylabel('Average Cost [€/kWh]', fontsize=14)
        plt.title(f'(d) {Year}', fontsize=16)
        plt.xticks(x, price_areas)
        plt.ylim(0, 0.035)
        plt.legend(loc='upper left')
        plt.tight_layout()
        plt.savefig(f"{Year}_cost_of_charging_per_tariff_and_price_area_barplot.png", dpi=300)
        

plt.show()




