import pandas as pd
from pathlib import Path
from functools import reduce

dfs = []

for pricearea in ["SE1", "SE2", "SE3", "SE4"]:
    file = r"C:\Users\perottie\Desktop\charge_bytariff_byarea\2021\charge_T3\{pricearea}_aggregates_charge.csv".format(pricearea=pricearea)

    df = pd.read_csv(file)

    # Drop sum column if present
    df = df.drop(columns=["sum"], errors="ignore")

    # Melt
    df_long = df.melt(
        id_vars="time",
        var_name="trsp",
        value_name="value"
    )

    # Add price area
    df_long["priceareas"] = pricearea

    dfs.append(df_long)

# Combine all price areas
result = pd.concat(dfs, ignore_index=True)

# Optional: preserve x1, x2, ..., x188 ordering
result["trsp"] = pd.Categorical(
    result["trsp"],
    categories=[f"x{i}" for i in range(1, 189)],
    ordered=True
)

result = result.sort_values(
    ["time", "trsp", "priceareas"]
).reset_index(drop=True)

# Reorder columns
result = result[["time", "trsp", "priceareas", "value"]]

result = result.rename(columns={"time": "timestep"})

print(max(result["value"]))
print(min(result["value"]))

print(result)

# Save
result.to_csv(r"C:\Users\perottie\Desktop\charge_bytariff_byarea\2021\charge_T3\all_home_charge_collective_2021.csv", index=False)
