import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import os
import time
import glob

input_folder = r"C:\Users\corte\Documents\REGAL_ToyModel\Output"
output_folder = r"C:\Users\corte\Documents\REGAL_ToyModel\Netloads_20260312"

results_hh = os.path.join(input_folder, "ToyModelHH_results.csv")
results_apt = os.path.join(input_folder, "ToyModelAPT_results.csv")
results_netload = os.path.join(input_folder, "ToyModelHH_netload_mt.csv")

df = pd.read_csv(results_netload)
timestamps = df['time']
profiles = df.drop(columns=['time'])
x = df["time"].values
xtick_step = 4380
xticks = np.arange(0, len(x), xtick_step)

for col in profiles.columns:
    # Plot the profile
    plt.figure(figsize=(10, 6))
    plt.plot(timestamps, profiles[col], label=col)
    plt.title(f"{col} profile")
    plt.xlabel("timestep [15min interval]")
    plt.ylabel(f"{col} [kWh/h]")
    plt.xticks(xticks, [str(i) for i in xticks])
    plt.legend()
    plt.tight_layout()
    # Save the plot
    output_path = os.path.join(output_folder, f"{col}.png")
    plt.savefig(output_path)
    plt.close()