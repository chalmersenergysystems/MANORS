# House selection and EV assignment shared by all runs (all tariffs, areas, 1 and 2 EVs), so that REGAL gets the same
# households in the same order in every case, and a house with 2 EVs has the same first EV as with 1 EV.

using CSV, DataFrames, JSON3, Random

const WEEK_STEPS = 7 * 96                      # 15-min steps per week
selection_file(seed) = joinpath(INPUT_PATH, "house_selection_seed$(seed).csv")
final_selection_file(seed) = joinpath(INPUT_PATH, "house_selection_seed$(seed)_final.csv")
pool_file() = joinpath(INPUT_PATH, "house_pool", "house_pool_representative.csv")

"""make_house_selection(; n_houses, seed=RANDOM_SEED, evshift_weeks=2, pool=pool_file())

Write `Input/house_selection_seed<seed>.csv`: the candidate houses in the order of `pool` (column `profile`; quality-
checked houses ordered so that every first part has the national share of houses without electric heating, see
`Input/house_pool/pool.py`), or with `pool=nothing` all houses with a known fuse size in a random (seeded) order,
each with two different EVs (`ev_1`, `ev_2`) and a whole-week time shift for each (`shift_1`, `shift_2`). EVs are
assigned from seeded shuffles of all EVs, one pass after the other. When there are fewer EVs than 2 x houses, each
further pass uses the next shift of 0, +1, -1, +2, -2, ... weeks (up to evshift_weeks), so a reused car charges on
other days; only after 2 x evshift_weeks + 1 passes does the same car with the same shift appear again.
The first 2-EV run takes the first `n_houses` candidates that solve and saves them as the final selection
(`final_selection_file`), used by all later runs. Returns the candidate table."""
function make_house_selection(; n_houses, seed=RANDOM_SEED, evshift_weeks=2, pool=pool_file())
    facility_df = CSV.read(joinpath(INPUT_PATH, "facility.csv"), DataFrame)
    fuse = Dict(String(r.facility_id) => r.contract_fuse_size for r in eachrow(facility_df))
    header = String.(propertynames(CSV.File(joinpath(INPUT_PATH, "all_fuse_safe_houses.csv"); limit=1)))  # house ids only
    houses = [p for p in header if p ∉ ("id_timestamp", "time") && !ismissing(get(fuse, p, missing))]
    rng = MersenneTwister(seed)
    if pool === nothing
        order = shuffle(rng, houses)
    else
        order = String.(CSV.read(pool, DataFrame; types=Dict(:profile => String)).profile)
        unknown = setdiff(order, houses)
        isempty(unknown) || error("$(length(unknown)) houses in $pool lack a load profile or a known fuse size, e.g. $(first(unknown)).")
        allunique(order) || error("$pool lists some houses more than once.")
    end
    length(order) >= n_houses || error("Only $(length(order)) candidate houses, cannot select $n_houses.")

    good_ids = all_ev_ids()
    length(good_ids) >= 2 || error("Need at least 2 EV profiles.")
    shifts = vcat(0, [s for w in 1:evshift_weeks for s in (w, -w)])      # 0, +1, -1, +2, -2, ...
    slots = Tuple{String, Int}[]
    npass = 0
    while length(slots) < 2 * length(order)
        npass += 1
        shift = shifts[mod1(npass, length(shifts))]
        for ev in shuffle(rng, good_ids)
            push!(slots, (ev, shift))
        end
    end
    needed = cld(2 * n_houses, length(good_ids))         # passes used by the first n_houses candidates
    needed > length(shifts) && @warn "The first $n_houses houses need $needed passes over the $(length(good_ids)) EVs but " *
        "there are only $(length(shifts)) different shifts: some houses get the same EV with the same shift " *
        "(more EVs or a larger evshift_weeks avoid it)."
    ev1, sh1, ev2, sh2 = String[], Int[], String[], Int[]
    for k in eachindex(order)
        a, b = slots[2k-1], slots[2k]
        if a[1] == b[1]                                   # two different cars per house: swap with a later slot
            j = findfirst(s -> s[1] != a[1], slots[2k+1:end])
            j === nothing && error("Cannot give house $k two different EVs.")
            j += 2k
            slots[2k], slots[j] = slots[j], slots[2k]
            b = slots[2k]
        end
        push!(ev1, a[1]); push!(sh1, a[2]); push!(ev2, b[1]); push!(sh2, b[2])
    end
    df = DataFrame(order=1:length(order), profile=order, fuse=[fuse[p] for p in order],
                   ev_1=ev1, shift_1=sh1, ev_2=ev2, shift_2=sh2, n_houses=n_houses)
    CSV.write(selection_file(seed), df)
    isfile(final_selection_file(seed)) && @warn "An old final selection exists ($(final_selection_file(seed))); delete it to start a new one."
    println("Saved $(selection_file(seed)): $(nrow(df)) candidate houses ($(count(==(16), df.fuse)) with 16 A) " *
            (pool === nothing ? "in random order, " : "in the order of $(basename(pool)), ") *
            "$(length(good_ids)) EVs, $(npass) pass(es) over the EVs. The first 2-EV run keeps the first $n_houses that solve.")
    return df
end

"Final selection (fixed by the first 2-EV run) if it exists, otherwise `nothing`."
read_final_selection(seed=RANDOM_SEED) =
    isfile(final_selection_file(seed)) ? CSV.read(final_selection_file(seed), DataFrame; types=Dict(:profile => String)) : nothing

read_candidates(seed=RANDOM_SEED) = CSV.read(selection_file(seed), DataFrame; types=Dict(:profile => String))

"EV ids and week shifts of a selection row for `n_ev` EVs (1 = first EV only)."
ev_spec(row, n_ev) = n_ev == 1 ? [(Symbol(row.ev_1), row.shift_1)] : [(Symbol(row.ev_1), row.shift_1), (Symbol(row.ev_2), row.shift_2)]

"Name of an EV in output files: id, plus the week shift if it is not zero (e.g. `abc123w-1`)."
ev_name(ev, shift) = shift == 0 ? String(ev) : "$(ev)w$(shift > 0 ? "+" : "")$(shift)"
