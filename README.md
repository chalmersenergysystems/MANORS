# MANORS

**MANORS** (Model Architecture for Netload Optimisation in Residential Systems) is an optimization model for household electricity costs with EV charging, used to study how different grid/network tariff designs affect residential electricity bills and EV charging behavior across the four Swedish bidding areas (SE1-SE4).

## Description

The model minimizes a household's (or a group of households') total annual electricity cost, consisting of electricity purchase cost (based on hourly area spot prices), public EV charging cost, and a monthly power tariff. The household is subject to a main fuse limit, an EV battery state-of-charge balance, and EV home/away availability profiles.

Input data (load profiles, facility/fuse metadata, EV mobility and charging data, and electricity prices) is read from `Input/`, and results are written as CSV files to `Output/`.

The following are the main scripts, found in [`src`](src):

+ shared input data loader ([inputdata.jl](src/inputdata.jl)) — reads prices, load profiles, facility/fuse metadata and EV data, and defines shared constants (`RANDOM_SEED`, `MONTH_TIMESTEPS`, `FUSE_TO_POWER_FACTOR`, `kWh_to_MWh`, ...)
+ individual power tariff model ([MANORS_powertariff.jl](src/MANORS_powertariff.jl))
+ collective power tariff model ([MANORS_collectivetariff.jl](src/MANORS_collectivetariff.jl))
+ results post-processing ([postprocess.jl](src/postprocess.jl))
+ plotting script ([plot_profiles.py](src/plot_profiles.py))
+ other work-in-progress versions of the model ([MANORS_singlerun.jl], [MANORS_loop.jl], [MANORS_multithread.jl])

## Model versions

This repository currently centers around two versions of the model, sharing the same optimization architecture (`makeparameters()`, `makevariables()`, `makeconstraints()`, `makemodel()`, `runmodel()`) but differing in how the power tariff is applied.

### Individual power tariff ([MANORS_powertariff.jl](src/MANORS_powertariff.jl))

Each household is optimized **independently**, one at a time, with its own EV assigned to it (randomly, but reproducibly via `RANDOM_SEED`).

* Main fuse limit (`maxpower`) is based on the household's own contracted fuse size.
* A monthly peak (`Peak[m]`) is tracked per household and penalized with a power tariff, `power_tariff`, with three selectable options:
    * `0` — No Tariff: no additional cost.
    * `1` — Daytime Tariff: only applies to peaks occurring 7 am-8 pm.
    * `2` — All Hours Tariff: applies to peaks at any hour.
* Results are written per household + assigned EV to `Output/Seed<seed>/AllRuns/Seed<seed>_<area>_Tariff<tariff>/`.

### Collective power tariff ([MANORS_collectivetariff.jl](src/MANORS_collectivetariff.jl))

All households in the selected area are optimized **jointly**, in a single model.

* Each household still has its own load, fuse-based connection limit, and EV, but the monthly peak (`Peak[m]`) is driven by the **sum** of all households' simultaneous purchased power.
* Only the "All Hours" collective power tariff is currently implemented (`Tariff3`).
* Because all households are solved together, this version is far more computationally demanding (one large model per area, instead of many small ones) — diagnostics for build/solve time and model size are printed during `makemodel()`.
* Results are written per household to `Output/Seed<seed>/AllRuns/Seed<seed>_<area>_Tariff3/`.

## Usage

> **Note:** this repository does not yet have a `Project.toml`/`Manifest.toml`, so dependencies must be installed manually into your active Julia environment.
>
> Input data (`Input/`) and results (`Output/`) are not distributed with the repository (see `.gitignore`). Simply place your own `Input/` and `Output/` folders at the repository root — all scripts resolve these paths relative to their own location (via `@__DIR__`), so no manual configuration or hardcoded paths are needed regardless of where the repo is cloned.
>
> [Gurobi](https://www.gurobi.com/) requires a separate commercial license — `HiGHS` works out of the box without one.

### Requirements

* Julia (tested with recent 1.x releases)
* [HiGHS](https://highs.dev/) (open-source, bundled via the `HiGHS.jl` package) and/or [Gurobi](https://www.gurobi.com/) (requires a license)
* Julia packages: `JuMP`, `HiGHS`, `Gurobi`, `CSV`, `DataFrames`, `PrettyTables`, `JSON3`, `Random`, `Dates`, `XLSX`, `AxisArrays`

Install them from the Julia REPL, e.g.:

```julia
using Pkg
Pkg.add(["JuMP", "HiGHS", "Gurobi", "CSV", "DataFrames", "PrettyTables", "JSON3", "XLSX", "AxisArrays"])
```

### Running a model

Navigate to the repository root and include the desired script, then call `runmodel()`:

```julia
cd("path/to/MANORS")

include("src/MANORS_powertariff.jl")
runmodel()
```

or for the collective version:

```julia
include("src/MANORS_collectivetariff.jl")
runmodel()
```

`runmodel()` interactively prompts for:

1. **Solver** — `HiGHS` or `Gurobi`
2. **Area** — `SE1`, `SE2`, `SE3`, `SE4`, or `all`
3. **Tariff option** (individual power tariff version only) — `0` (No Tariff), `1` (Daytime Tariff), or `2` (All Hours Tariff)

### Output

Each run produces one CSV file per household (and its assigned EV), named `MANORS_<area>_<profile>_EV_<ev_id>_Tariff<tariff>.csv`, with columns:

| Column              | Description                                                 |
|---------------------|-------------------------------------------------------------|
| `time`              | Timestep index (15-min resolution, 1:35040 over a year)     |
| `load`              | Household baseline load (kWh/15-min)                        |
| `buy`               | Total power purchased from the grid (kWh/15-min)            |
| `baseline`          | Household load + originally logged EV charging (kWh/15-min) |
| `optimized`         | Household optimized netload (kWh/15-min)                    |
| `demand_ev`         | EV driving energy demand (kWh/15-min)                       |
| `logged_ev`         | Originally logged EV charging profile (kWh/15-min)          |
| `charge_ev`         | Optimized home EV charging (kWh/15-min)                     |
| `public_charge_ev`  | Optimized public EV charging (kWh/15-min)                   |
| `soc_ev`            | EV battery state of charge (kWh)                            |

Files are saved under `Output/Seed<seed>/AllRuns/Seed<seed>_<area>_Tariff<tariff>/` (individual power tariff, `tariff` = 0/1/2) or `Output/Seed<seed>/AllRuns/Seed<seed>_<area>_Tariff3/` (collective power tariff) — see [Post-processing](#post-processing) below to aggregate and visualize results.

### Post-processing

[postprocess.jl](src/postprocess.jl) aggregates the per-household CSVs written by the two tariff models above. Run in this order:

1. `build_netload_profiles(seed)` — adds an `optimized` (net grid draw) column to every raw per-household run CSV.
2. `collect_results(seed, tariff, area)`, or interactively `collect_results()` — aggregates all households in an area into per-metric wide CSVs (one column per household), written to `Output/Seed<seed>/Aggregates/Seed<seed>_Tariff<tariff>/`.
3. `find_peaks()` — cross-seed summary of monthly peak (import) and dip (export) power per area/household, written to `Output/Aggregates/Summary/`.
4. `compare_tariffs_monthly()` — compact monthly peak/dip comparison across all 4 tariff options (No/Daytime/All Hours/Collective Tariff).
5. `average_areas(seed, tariff)` — averages a seed's per-area aggregates (SE1-SE4) into a single Sweden-wide series.

> **Note:** `load_profiles()` and `build_profiles()`, in the same file, are obsolete leftovers from an earlier PV + home battery (BESS) model variant ([MANORS_loop.jl](src/MANORS_loop.jl) / [MANORS_multithread.jl](src/MANORS_multithread.jl)) and are unrelated to the two tariff models above; they are kept only for reference.

Use [plot_profiles.py](src/plot_profiles.py) to visualize the resulting profiles.
