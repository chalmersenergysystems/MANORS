import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import os
import time
import glob

gridarea = "SE4"     # SE1, SE2, SE3, SE4

# Input/, Output/ and Plots/ folders live at the repository root (git-ignored).
# Resolved relative to this file's location, so it works regardless of where the repo is cloned to.
project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
input_folder = os.path.join(project_root, "Input")
output_folder = os.path.join(project_root, "Output")
synth_folder = os.path.join(input_folder, "synth_profiles")

plots_root = os.path.join(project_root, "Plots")
plot_folder = os.path.join(plots_root, f"Netloads_{gridarea}")
dummy_folder = os.path.join(plots_root, f"Dummyloads_{gridarea}")
poster_folder = os.path.join(plots_root, "Poster_plots")
hh_folder = os.path.join(plots_root, "HH_loads")
apt_folder = os.path.join(plots_root, "APT_loads")

os.makedirs(plot_folder, exist_ok=True)
os.makedirs(dummy_folder, exist_ok=True)
os.makedirs(poster_folder, exist_ok=True)
os.makedirs(hh_folder, exist_ok=True)
os.makedirs(apt_folder, exist_ok=True)

# results_hh = os.path.join(output_folder, "ToyModelHH_results.csv")
# results_apt = os.path.join(output_folder, "ToyModelAPT_results.csv")
results_netload = os.path.join(output_folder, f"ToyModelHH_netload_{gridarea}_synth.csv")
dummyloads = os.path.join(output_folder, f"ToyModelHH_dummyloads_{gridarea}_synth.csv")

load_HH = os.path.join(input_folder, "HH_sampled_profiles_merged.csv")
load_APT = os.path.join(input_folder, "APT_sampled_profiles_merged.csv")
if gridarea == "SE1":
    genPV = os.path.join(synth_folder, "pv_profiles_Norrbotten.csv")
elif gridarea == "SE2":
    genPV = os.path.join(synth_folder, "pv_profiles_Jämtland.csv")
elif gridarea == "SE3":
    genPV = os.path.join(synth_folder, "pv_profiles_Stockholm.csv")
elif gridarea == "SE4":
    genPV = os.path.join(synth_folder, "pv_profiles_Skåne.csv")

df = pd.read_csv(results_netload)       # optimized netload profiles
# df = pd.read_csv(dummyloads)            # "dummy" netload profiles
timestamps = df['time']
profiles = df.drop(columns=['time'])
x = df["time"].values
xtick_step = 4380
xticks = np.arange(0, len(x), xtick_step)

# df_load = pd.read_csv(load_HH)                  # household load profiles
df_load = pd.read_csv(load_APT)                  # apartment load profiles
profiles = df_load
fs = 14

for col in profiles.columns:
    # Plot the profile
    plt.figure(figsize=(14, 6))
    plt.plot(timestamps, profiles[col], label=col)

    plt.title(f"Apartment load profile", fontsize=fs*1.5, pad=20)
    plt.xlabel("Timestep [15min interval]", fontsize=fs*1.2)
    plt.ylabel(f"Electricity consumption [kWh/15min]", fontsize=fs*1.2)
    plt.xticks(xticks, [str(i) for i in xticks])
    plt.tick_params(axis='both', which='major', labelsize=fs)
    # plt.title(f"{col} profile")
    # plt.xlabel("Timestep [15min interval]")
    # plt.ylabel(f"Netload [kWh/15min]")
    # plt.xticks(xticks, [str(i) for i in xticks])
    # plt.legend()
    plt.tight_layout()
    # Save the plot
    # output_path = os.path.join(plot_folder, f"{col}.png")       # optimized netload profiles
    output_path = os.path.join(apt_folder, f"{col}.png")      # "dummy" netload profiles
    plt.savefig(output_path)
    plt.close()

# # Select the time range of interest
# day_before = 171
# start_time = 4*24 * day_before + 1          # 21st June 2024, 00:00
# end_time = 4*24 * (day_before + 1)          # 22nd June 2024, 23:45
# timeslice = slice(start_time, end_time)

# # Select the corresponding timestamps for the x-axis
# xtick_step = 4
# xticks = np.arange(0, end_time - start_time, xtick_step)

# # # Plot the profiles for the selected time range
# # for col in profiles.columns:
# #     plt.figure(figsize=(10, 6))
# #     relative_time = np.arange(len(profiles[col][timeslice]))
# #     plt.plot(relative_time, profiles[col][timeslice], label=col)
# #     # plt.bar(relative_time, profiles[col][timeslice], label=col, width=1.0)
# #     plt.title(f"{col} profile (21st June 2024)")
# #     plt.xlabel("timestep [15min interval]")
# #     plt.ylabel(f"Netload [kWh/15min]")
# #     plt.xticks(xticks, [str(i) for i in xticks])
# #     # plt.legend()
# #     plt.tight_layout()
# #     # output_path = os.path.join(plot_folder, f"day10_{col}.png")        # optimized netload profiles
# #     output_path = os.path.join(dummy_folder, f"day10_{col}.png")      # "dummy" netload profiles
# #     plt.savefig(output_path)
# #     plt.close()

fs = 14

# poster_profile = ["run_34_loadf88f1f56-0a4a-13a6-d241-02315fc5003d_bessBESS10_genaba38435-084f-7e92-2743-e144bac50f00"]
prefix = "run_34_loadf88f1f56-0a4a-13a6-d241-02315fc5003d_"

# Load both files
df_base = pd.read_csv(dummyloads)
df_opt  = pd.read_csv(results_netload)

base_col = next(col for col in df_base.columns if col.startswith(prefix))
print(f"Identified baseline column: {base_col}")
opt_col  = next(col for col in df_opt.columns  if col.startswith(prefix))
print(f"Identified optimized column: {opt_col}")

timestamps = df_base['time']
profiles = df_base.drop(columns=['time'])
x = df_base["time"].values
xtick_step = 4380
xticks = np.arange(0, len(x), xtick_step)

# Plot the profile
plt.figure(figsize=(14, 6))
plt.plot(timestamps, df_base[base_col])
plt.title(f"Baseline netload profile", fontsize=fs*1.5, pad=20)
plt.xlabel("Timestep [15min interval]", fontsize=fs*1.2)
plt.ylabel(f"Netload [kWh/15min]", fontsize=fs*1.2)
plt.xticks(xticks, [str(i) for i in xticks])
plt.tick_params(axis='both', which='major', labelsize=fs)
# plt.legend()
plt.tight_layout()
# Save the plot
output_path = os.path.join(poster_folder, f"base_{gridarea}.png")      # "dummy" netload profiles
plt.savefig(output_path)
plt.close()

timestamps = df_opt['time']
profiles = df_opt.drop(columns=['time'])
x = df_opt["time"].values
xtick_step = 4380
xticks = np.arange(0, len(x), xtick_step)

# Plot the profile
plt.figure(figsize=(14, 6))
plt.plot(timestamps, df_opt[opt_col])
plt.title(f"Optimized netload profile", fontsize=fs*1.5, pad=20)
plt.xlabel("Timestep [15min interval]", fontsize=fs*1.2)
plt.ylabel(f"Netload [kWh/15min]", fontsize=fs*1.2)
plt.xticks(xticks, [str(i) for i in xticks])
plt.tick_params(axis='both', which='major', labelsize=fs)
# plt.legend()
plt.tight_layout()
# Save the plot
output_path = os.path.join(poster_folder, f"opt_{gridarea}.png")       # optimized netload profiles
plt.savefig(output_path)
plt.close()

df_load = pd.read_csv(load_HH)

# Plot the profile
plt.figure(figsize=(14, 6))
plt.plot(timestamps, df_load['f88f1f56-0a4a-13a6-d241-02315fc5003d'])
plt.title(f"Household load profile", fontsize=fs*1.5, pad=20)
plt.xlabel("Timestep [15min interval]", fontsize=fs*1.2)
plt.ylabel(f"Electricity consumption [kWh/15min]", fontsize=fs*1.2)
plt.xticks(xticks, [str(i) for i in xticks])
plt.tick_params(axis='both', which='major', labelsize=fs)
# plt.legend()
plt.tight_layout()
# Save the plot
output_path = os.path.join(poster_folder, f"load.png")       # household load profiles
plt.savefig(output_path)
plt.close()

df_genPV = pd.read_csv(genPV)

if gridarea == "SE1":
    gen_col = "x484"
elif gridarea == "SE2":
    gen_col = "x27"
elif gridarea == "SE3":
    gen_col = "x255"
elif gridarea == "SE4":
    gen_col = "x787"

# Plot the profile
plt.figure(figsize=(14, 6))
plt.plot(timestamps, df_genPV[gen_col])
plt.title(f"PV production profile", fontsize=fs*1.5, pad=20)
plt.xlabel("Timestep [15min interval]", fontsize=fs*1.2)
plt.ylabel(f"Electricity generation [kWh/15min]", fontsize=fs*1.2)
plt.xticks(xticks, [str(i) for i in xticks])
plt.tick_params(axis='both', which='major', labelsize=fs)
# plt.legend()
plt.tight_layout()
# Save the plot
output_path = os.path.join(poster_folder, f"gen_{gridarea}.png")       # PV production profiles
plt.savefig(output_path)
plt.close()

# Plot the profiles for the selected time range
# for col in poster_profile:
#     plt.figure(figsize=(10, 6))
#     relative_time = np.arange(len(profiles[col][timeslice]))
#     plt.plot(relative_time, profiles[col][timeslice], label=col)
#     # plt.bar(relative_time, profiles[col][timeslice], label=col, width=1.0)
#     # plt.title(f"Optimized netload profile - 21st June 2024")
#     plt.title(f"Baseline netload profile - 21st June 2024")
#     plt.xlabel("Timestep [15min interval]")
#     plt.ylabel(f"Netload [kWh/15min]")
#     plt.xticks(xticks, [str(i) for i in xticks])
#     # plt.legend()
#     plt.tight_layout()
#     # output_path = os.path.join(poster_folder, f"optimized_netload_day172.png")        # optimized netload profiles
#     output_path = os.path.join(poster_folder, f"baseline_netload_day172.png")      # "dummy" netload profiles
#     plt.savefig(output_path)
#     plt.close()

# Load both files
df_base = pd.read_csv(dummyloads)
df_opt  = pd.read_csv(results_netload)

timestamps = df_base['time']
x_range    = np.arange(len(timestamps))

# base_col = "run_34_loadf88f1f56-0a4a-13a6-d241-02315fc5003d_genaba38435-084f-7e92-2743-e144bac50f00"
# opt_col  = "run_34_loadf88f1f56-0a4a-13a6-d241-02315fc5003d_bessBESS10_genaba38435-084f-7e92-2743-e144bac50f00"

prefix = "run_34_loadf88f1f56-0a4a-13a6-d241-02315fc5003d_"

base_col = next(col for col in df_base.columns if col.startswith(prefix))
opt_col  = next(col for col in df_opt.columns  if col.startswith(prefix))

b = df_base[base_col].values
o = df_opt[opt_col].values

# Common area: from 0 up to the smaller absolute value (preserving sign)
same_sign = np.sign(b) == np.sign(o)
common = np.where(same_sign, np.sign(b) * np.minimum(np.abs(b), np.abs(o)), 0)

# Font size for the poster
fs = 16

fig, ax = plt.subplots(figsize=(14, 6))

# Blue: shared area between the two profiles
ax.fill_between(x_range, 0, common, color='blue', alpha=0.3, label='Common netload')

# Red: extra area where baseline > optimized (in abs terms)
ax.fill_between(x_range, common, b,
                where=(np.abs(b) > np.abs(o)),
                color='red', alpha=0.4, label='Baseline only')

# Green: extra area where optimized > baseline (in abs terms)
ax.fill_between(x_range, common, o,
                where=(np.abs(o) >= np.abs(b)),
                color='green', alpha=0.4, label='Optimized only')

# ax.plot(x_range, b, color='darkred',   linewidth=0.8, label='Baseline')
# ax.plot(x_range, o, color='darkgreen', linewidth=0.8, label='Optimized')

ax.axhline(0, color='black', linewidth=0.5, linestyle='--')
ax.set_title("Netload shift: Baseline vs Optimized")
ax.set_xlabel("Timestep [15min interval]")
ax.set_ylabel("Netload [kWh/15min]")
ax.set_xticks(xticks)
ax.set_xticklabels([str(i) for i in xticks])
ax.legend()
plt.tight_layout()
plt.savefig(os.path.join(poster_folder, f"netload_shift_{gridarea}.png"))
plt.close()

days_of_interest = {
    9:  "10th January 2025",
    171: "21st June 2024",
}

weeks_of_interest = {
    5:  "Week 2 (6-12 January 2025)",
    167: "Week 25 (17-23 June 2024)",
}

# for day, label in days_of_interest.items():
for day, label in weeks_of_interest.items():
    start_time = 4*24 * day + 1
    end_time   = 4*24 * (day + 7)
    timeslice  = slice(start_time, end_time)
    x_range    = np.arange(end_time - start_time)

    b = df_base[base_col].values[timeslice]
    o = df_opt[opt_col].values[timeslice]

    same_sign = np.sign(b) == np.sign(o)
    common = np.where(same_sign, np.sign(b) * np.minimum(np.abs(b), np.abs(o)), 0)

    xtick_step = 24
    xticks = np.arange(0, end_time - start_time, xtick_step)

    fig, ax = plt.subplots(figsize=(18, 6))

    ax.fill_between(x_range, 0, common, color='steelblue', alpha=0.3, label='Common netload')
    ax.fill_between(x_range, common, b,
                    where=(np.abs(b) > np.abs(o)),
                    color='darkorange', alpha=0.4, label='Baseline only')
    ax.fill_between(x_range, common, o,
                    where=(np.abs(o) >= np.abs(b)),
                    color='mediumpurple', alpha=0.4, label='Optimized only')
    
    # ax.plot(x_range, b, color='darkred',   linewidth=0.8, label='Baseline')
    # ax.plot(x_range, o, color='darkgreen', linewidth=0.8, label='Optimized')

    ax.axhline(0, color='black', linewidth=0.5, linestyle='--')
    ax.set_title(f"Netload shift: Baseline vs Optimized - {gridarea} {label}", fontsize=fs*1.5, pad=20)
    ax.set_xlabel("Timestep [15min interval]", fontsize=fs*1.2)
    ax.set_ylabel("Netload [kWh/15min]", fontsize=fs*1.2)
    ax.tick_params(axis='both', which='major', labelsize=fs)
    ax.set_xticks(xticks)
    ax.set_xticklabels([str(i) for i in xticks])
    ax.legend(fontsize=fs)
    plt.tight_layout()
    # plt.savefig(os.path.join(poster_folder, f"netload_shift_day{day+1}.png"))
    plt.savefig(os.path.join(poster_folder, f"netload_shift_{gridarea}_week{round(day/7)+1}_synth.png"))
    plt.close()