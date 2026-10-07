# Postprocessing script for tariff article 

from matplotlib import colors
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
from pandas.api.types import CategoricalDtype

# --- CONSTANTS AND SETTINGS ---
MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
MAX_CHARGING_POWER = 22  # Cap charging values at 22 kW
OUTPUT_DPI = 300  # Resolution for saved figures
COLORS = ["#FC7C84FF",  "#5971FA", "#C771F9", "#61AA52"]
LOGGED_COLOR = "#23610A"
VEHICLE_COUNT = 188
POWER_TARIFF_COST = 7.4 #€/kW/month

# --- DATA LOADING AND PREPROCESSING ---    
# Load household demand data 
timeStepsPerHour = 4
HouseholdDemand = pd.read_csv('sum_houseload_main_selection.csv', sep=',')/VEHICLE_COUNT * timeStepsPerHour # Convert from kWh to kW

time_index = pd.date_range(start='2023-01-01', end='2023-12-31 23:45', freq='15min')
peak_sum_data = pd.read_csv("peak_sum_Seed18_main_selection.csv")

HouseholdDemand['Month'] = time_index.month
Monthly_Household_Demand = HouseholdDemand.groupby('Month')['demand'].max()

# Load logged charging data
LoggedCharging = pd.read_csv('chargeenergy_2.csv', sep=';')  * timeStepsPerHour  # Convert from kWh to kW
# sum all columns but the first one (which is the timestamp) to get total logged charging
LoggedCharging['Logged Charging'] = LoggedCharging.iloc[:, 1:].sum(axis=1) /VEHICLE_COUNT
LoggedCharging['Month'] = time_index.month

# Calculate total load
Total_Load_logged_hh = LoggedCharging['Logged Charging'] + HouseholdDemand['demand']
Monthly_Total_Load_logged_hh = Total_Load_logged_hh.groupby(HouseholdDemand['Month']).max()
Monthly_logged = LoggedCharging['Logged Charging'].groupby(LoggedCharging['Month']).max()

# Load peak data
df_peak_sum = pd.DataFrame(peak_sum_data)

#Rename months
df_peak_sum['Month'] = df_peak_sum['Month'].replace({'m1':'Jan', 'm2':'Feb', 'm3':'Mar', 'm4':'Apr', 'm5':'May', 'm6':'Jun', 'm7':'Jul', 'm8':'Aug', 'm9':'Sep', 'm10':'Oct', 'm11':'Nov', 'm12':'Dec'})

#sort values by month order
month_cat = CategoricalDtype(categories=MONTHS, ordered=True)
df_peak_sum['Month'] = df_peak_sum['Month'].astype(str)
df_peak_sum['Month'] = df_peak_sum['Month'].astype(month_cat)
df_peak_sum = df_peak_sum.sort_values('Month')

# --- CALCULATE MONTHLY STATISTICS ---
# Calculate means per vehicle and standard error of the mean
Monthly_No_tariff = df_peak_sum.groupby('Month', observed=False)['No Tariff'].mean() / VEHICLE_COUNT
Monthly_All_hours = df_peak_sum.groupby('Month', observed=False)['All hours'].mean() / VEHICLE_COUNT
Monthly_Daytime = df_peak_sum.groupby('Month', observed=False)['Daytime'].mean() / VEHICLE_COUNT
Monthly_Collective = df_peak_sum.groupby('Month', observed=False)['Collective'].mean() / VEHICLE_COUNT

print('Number of vehicles:', VEHICLE_COUNT)
print('Monthly_Collective:', Monthly_Collective)
print('Monthly_logged:', Monthly_logged)
print('Monthly_No_tariff:', Monthly_No_tariff)
print('Monthly_All_hours:', Monthly_All_hours)
print('Monthly_Daytime:', Monthly_Daytime)

# Calculate standard deviations
Monthly_No_tariff_std = df_peak_sum.groupby('Month', observed=False)['No Tariff'].std() / (np.sqrt(4) * VEHICLE_COUNT)
Monthly_All_hours_std = df_peak_sum.groupby('Month', observed=False)['All hours'].std() / (np.sqrt(4) * VEHICLE_COUNT)
Monthly_Daytime_std = df_peak_sum.groupby('Month', observed=False)['Daytime'].std() / (np.sqrt(4) * VEHICLE_COUNT)
Monthly_Collective_std = df_peak_sum.groupby('Month', observed=False)['Collective'].std() / (np.sqrt(4) * VEHICLE_COUNT)

# Create summary dataframe
df_peak = pd.DataFrame({
    'Month': MONTHS,
    'No Tariff': Monthly_No_tariff.values,
    'All hours': Monthly_All_hours.values,
    'Daytime': Monthly_Daytime.values,
    'Collective': Monthly_Collective.values,
    'No Tariff std': Monthly_No_tariff_std.values,
    'All hours std': Monthly_All_hours_std.values,
    'Daytime std': Monthly_Daytime_std.values,
    'Collective std': Monthly_Collective_std.values,
    'Household Demand': Monthly_Household_Demand,
    'Total Load Logged + HH': Monthly_Total_Load_logged_hh.values
})
df_peak.set_index('Month', inplace=True)

# --- DETAILED PER-VEHICLE ANALYSIS ---
# Load additional data for per-vehicle analysis
ev_used = pd.read_csv('ev_mapping.csv', sep=',')
LoggedCharging_detailed = pd.read_csv('chargeenergy_2.csv', sep=';')

# Filter and process charging data
CarsIncluded = pd.unique(ev_used['ev_id'])
if len(CarsIncluded) != VEHICLE_COUNT:
    print(f"Warning: Expected {VEHICLE_COUNT} vehicles, but found {len(CarsIncluded)} in the data.")

LoggedCharging_detailed = LoggedCharging_detailed[LoggedCharging_detailed.columns[LoggedCharging_detailed.columns.isin(CarsIncluded)]]
print(f"Loaded logged charging data for {LoggedCharging_detailed.shape[1]} vehicles.")
LoggedCharging_detailed = LoggedCharging_detailed * timeStepsPerHour  # Convert from kWh to kW
# Clean data: remove negative values and cap at max power
numeric_columns = LoggedCharging_detailed.select_dtypes(include=[np.number]).columns
LoggedCharging_detailed[numeric_columns] = LoggedCharging_detailed[numeric_columns].clip(lower=0, upper=MAX_CHARGING_POWER)

# Add month information
LoggedCharging_detailed = LoggedCharging_detailed.copy()
LoggedCharging_detailed['Month'] = time_index.month
vehicle_columns = [col for col in LoggedCharging_detailed.columns if col != 'Month']

# Calculate total load (vehicle + household) for all vehicles simultaneously
Total_load_logged_store = LoggedCharging_detailed[vehicle_columns].add(HouseholdDemand['demand'].values, axis=0)

# Calculate peak values by month
PeakPPervehicle = LoggedCharging_detailed.groupby('Month')[vehicle_columns].max()
PeakPHouseholdLogged = Total_load_logged_store.groupby(time_index.month).max()

# Calculate total load sum across all vehicles
Load_summed = Total_load_logged_store.sum(axis=1)

# Ensure dataframe is purely contiguous before appending new columns
Total_load_logged_store = Total_load_logged_store.copy() 
Total_load_logged_store['Month'] = time_index.month
Total_load_logged_store['Total Load'] = Load_summed

# Calculate monthly maximum of total load
Max_monthly_total_load = Total_load_logged_store.groupby('Month')['Total Load'].max()
CommonPPeakLogged = Max_monthly_total_load / VEHICLE_COUNT

# Calculate statistics across vehicles
AvgPeakP = PeakPPervehicle.mean(axis=1)
AvgPeakPHouseholdLogged = PeakPHouseholdLogged.mean(axis=1)
StdPeakPower = PeakPPervehicle.std(axis=1)
StdPeakPowerHouseholdLogged = PeakPHouseholdLogged.std(axis=1)

# --- VISUALIZATION FUNCTIONS ---
def create_comparison_bar_plot():
    """Create bar plot including logged data with a secondary y-axis showing per-vehicle values"""
    fig, ax = plt.subplots(figsize=(10, 5))
    bar_width = 0.16
    positions = np.arange(len(MONTHS))
    
    # Plot totals (per-month * VEHICLE_COUNT) on primary axis
    ax.bar(positions - 2*bar_width, df_peak['Total Load Logged + HH']*VEHICLE_COUNT, bar_width, 
           label='Logged charging', alpha=0.9, color=LOGGED_COLOR)
    ax.bar(positions - bar_width, df_peak['No Tariff']*VEHICLE_COUNT, bar_width,
           label='No tariff', alpha=0.9, color=COLORS[0])
    ax.bar(positions, df_peak['Daytime']*VEHICLE_COUNT, bar_width,
           label='Daytime tariff', alpha=0.9, color=COLORS[2])
    ax.bar(positions + bar_width, df_peak['All hours']*VEHICLE_COUNT, bar_width,
           label='All hours tariff', alpha=0.9, color=COLORS[1])
    ax.bar(positions + 2*bar_width, df_peak['Collective']*VEHICLE_COUNT, bar_width,
          label='Collective tariff', alpha=0.9, color=COLORS[3])

    ax.set_xticks(positions)
    ax.set_xticklabels(MONTHS, rotation=45)
    ax.set_ylabel('Total peak power [kW]', fontsize=14)
    ax.set_xlabel('Month', fontsize=14)
    ax.grid(axis='y', linestyle='--', alpha=0.3)
    
    # Secondary axis: per-vehicle values (same bars interpreted per vehicle)
    ax2 = ax.twinx()
    # map primary axis limits to per-vehicle scale by dividing by VEHICLE_COUNT
    prim_ylim = ax.get_ylim()
    ax2.set_ylim(prim_ylim[0] / VEHICLE_COUNT, prim_ylim[1] / VEHICLE_COUNT)
    ax2.set_ylabel('Peak power per household [kW]', fontsize=14)

    # create a legend for the primary bars only
    # ax.legend(loc='upper center')
    ax.legend(
        loc='upper center',
        bbox_to_anchor=(0.5, 1.1),
        ncol=5,
        frameon=True,
        facecolor='white'
    )
    plt.tight_layout()
    plt.savefig("peak_power_2024_seed_18_box_legend.png", dpi=OUTPUT_DPI)

peak_individ = pd.read_csv('individual_peaks_Seed18_main_selection.csv')
peak_individ = peak_individ[peak_individ['priceareas'] == 'SE3']  # Filter for SE3 area
peak_individ['Month'] = peak_individ['Month'].replace({'m1':'Jan', 'm2':'Feb', 'm3':'Mar', 'm4':'Apr', 'm5':'May', 'm6':'Jun', 'm7':'Jul', 'm8':'Aug', 'm9':'Sep', 'm10':'Oct', 'm11':'Nov', 'm12':'Dec'})

def create_boxplot():
    """Create boxplot of peak loads by month and tariff"""
    # Prepare data for boxplot
    melted_data = peak_individ.melt(
        id_vars=['Month'],
        value_vars=['No Tariff', 'All hours', 'Daytime', 'Collective']
    )

    # Ensure Month is an ordered categorical (calendar order)
    month_cat = CategoricalDtype(categories=MONTHS, ordered=True)
    # If FusePerHH Month is like 'm1' already replaced above to 'Jan'..'Dec'
    melted_data['Month'] = melted_data['Month'].astype(str)
    melted_data['Month'] = melted_data['Month'].astype(month_cat)

    # Add logged data to the comparison
    PeakPHouseholdLogged_reset = PeakPHouseholdLogged.reset_index(drop=True)
    PeakPHouseholdLogged_reset['Month'] = range(1, 13)
    PeakPHouseholdLogged_reset['Month'] = PeakPHouseholdLogged_reset['Month'].replace(
        {i+1: MONTHS[i] for i in range(12)}
    )
    PeakPHouseholdLogged_reset['Month'] = PeakPHouseholdLogged_reset['Month'].astype(month_cat)

    # Melt the logged data
    PeakPHouseholdLogged_reset_melted = PeakPHouseholdLogged_reset.melt(
        id_vars=['Month'],
        value_vars=PeakPHouseholdLogged.columns[:-1]  # Exclude Month column
    )
    PeakPHouseholdLogged_reset_melted['variable'] = 'Logged'
    PeakPHouseholdLogged_reset_melted['Month'] = PeakPHouseholdLogged_reset_melted['Month'].astype(month_cat)

    # Individual tariff subplots
    plotnames = ['(b) No tariff', '(d) All hours tariff', '(c) Daytime tariff', '(e) Collective tariff']
    tariffs = ['No Tariff', 'All hours', 'Daytime', 'Collective']
    for tariff in tariffs:
        plt.figure(figsize=(7, 5))
        ax = sns.boxplot(
            x='Month',
            y='value',
            data=melted_data[melted_data['variable'] == tariff],
            order=MONTHS,
            color=COLORS[3],
            fliersize=0
        )
        plt.xticks(rotation=45)
        tariff_index = tariffs.index(tariff)
        plt.title(f'{plotnames[tariff_index]}', fontsize=16)
        plt.ylabel('Peak power [kW]', fontsize=14)
        plt.xlabel('Month', fontsize=14)
        plt.grid(axis='y', linestyle='--', alpha=0.3)
        plt.ylim(0, 25)
        plt.tight_layout()
        plt.savefig(f"peak_power_boxplot_{tariff.replace(' ', '_').lower()}.png", dpi=OUTPUT_DPI)

    #Now create the same plot for logged data
    plt.figure(figsize=(7, 5))
    ax = sns.boxplot(
        x='Month',
        y='value',
        data=PeakPHouseholdLogged_reset_melted,
        order=MONTHS,
        color=COLORS[3],
        fliersize=0
    )
    plt.xticks(rotation=45)
    plt.title('(a) Logged charging', fontsize=16)
    plt.ylim(0, 25)
    plt.ylabel('Peak power [kW]', fontsize=14)
    plt.xlabel('Month', fontsize=14)
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.tight_layout()
    plt.savefig("peak_power_boxplot_logged_only.png", dpi=OUTPUT_DPI)

def calculate_tariff_costs():
    """Calculate monthly tariff costs based on peak loads"""
    tariff_costs = Monthly_No_tariff * POWER_TARIFF_COST
    print("Monthly Tariff Costs (€):")
    print(tariff_costs)
    
    tariff_cost_allhours = Monthly_All_hours * POWER_TARIFF_COST
    print("Monthly Tariff Costs for All Hours (€):")
    print(tariff_cost_allhours)

    tariff_cost_daytime = Monthly_Daytime * POWER_TARIFF_COST
    print("Monthly Tariff Costs for Daytime (€):")
    print(tariff_cost_daytime)

    tariff_cost_collective = Monthly_Collective * POWER_TARIFF_COST
    print("Monthly Tariff Costs for Collective (€):")
    print(tariff_cost_collective)

    Annual_costs = {
        'No Tariff': tariff_costs.sum(),
        'All hours': tariff_cost_allhours.sum(),
        'Daytime': tariff_cost_daytime.sum(),
        'Collective': tariff_cost_collective.sum()
    }

    print("Annual Tariff Costs (€):")
    print(Annual_costs)

# Function calls to generate plots and calculate costs
create_comparison_bar_plot()
create_boxplot()
calculate_tariff_costs()

plt.show()
