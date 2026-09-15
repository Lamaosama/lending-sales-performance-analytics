"""
Generate a fully SYNTHETIC dataset for a consumer-lending sales network.

Nothing here comes from a real company. The tables only mimic the *shape* of a
typical point-of-sale lending business: sales locations, sales agents,
loan products, applications and monthly targets.

A few realistic patterns are planted on purpose so the analysis has something
to find (low-approval locations, approved-but-not-disbursed leakage, new-agent
ramp-up, weekday effects and monthly seasonality).

Run:  python src/generate_data.py
Out:  data/*.csv  and  data/lending.db (SQLite)
"""

from pathlib import Path
import sqlite3

import numpy as np
import pandas as pd

SEED = 42
START, END = "2026-01-01", "2026-06-30"
N_LOCATIONS = 150

rng = np.random.default_rng(SEED)
ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
DATA.mkdir(exist_ok=True)

# --------------------------------------------------------------------------
# 1. Products
# --------------------------------------------------------------------------
products = pd.DataFrame(
    {
        "product_id": ["P1", "P2", "P3", "P4"],
        "product_name": ["Mobile Phones", "Home Appliances", "Furniture", "Education"],
        "avg_ticket_egp": [18_000, 32_000, 45_000, 25_000],
        "approval_adj": [0.04, 0.00, -0.05, -0.02],
    }
)

# --------------------------------------------------------------------------
# 2. Locations
# --------------------------------------------------------------------------
regions = ["Greater Cairo", "Alexandria", "Delta", "Canal", "Upper Egypt"]
region_w = [0.40, 0.18, 0.20, 0.10, 0.12]
loc_types = ["Mall Kiosk", "Electronics Store", "Furniture Store"]
type_w = [0.35, 0.40, 0.25]

loc_ids = [f"LOC{i:03d}" for i in range(1, N_LOCATIONS + 1)]
locations = pd.DataFrame(
    {
        "location_id": loc_ids,
        "region": rng.choice(regions, N_LOCATIONS, p=region_w),
        "location_type": rng.choice(loc_types, N_LOCATIONS, p=type_w),
        "opened_date": pd.to_datetime("2023-01-01")
        + pd.to_timedelta(rng.integers(0, 1_000, N_LOCATIONS), unit="D"),
    }
)

# Hidden drivers (not exported): traffic, applicant quality, disbursement leakage
traffic = rng.lognormal(mean=0.0, sigma=0.35, size=N_LOCATIONS)
quality = np.clip(rng.normal(0.64, 0.05, N_LOCATIONS), 0.50, 0.78)
leakage = np.full(N_LOCATIONS, 0.08)

planted = rng.choice(N_LOCATIONS, 22, replace=False)
low_quality_idx = planted[:12]   # many applications, few approvals
leakage_idx = planted[12:]       # approved but customers don't complete
quality[low_quality_idx] = rng.normal(0.44, 0.03, 12)
traffic[low_quality_idx] *= 1.25
leakage[leakage_idx] = rng.uniform(0.28, 0.38, 10)

region_traffic = {"Greater Cairo": 1.10, "Alexandria": 1.00, "Delta": 0.92, "Canal": 0.90, "Upper Egypt": 0.85}
traffic *= locations["region"].map(region_traffic).to_numpy()

# --------------------------------------------------------------------------
# 3. Agents
# --------------------------------------------------------------------------
agent_rows = []
aid = 1
for i, loc in enumerate(loc_ids):
    for _ in range(rng.integers(1, 5)):  # 1-4 agents per location
        if rng.random() < 0.22:  # hired during the period -> ramp-up
            hire = pd.Timestamp(START) + pd.Timedelta(days=int(rng.integers(0, 150)))
        else:
            hire = pd.Timestamp(START) - pd.Timedelta(days=int(rng.integers(60, 900)))
        agent_rows.append(
            {
                "agent_id": f"AG{aid:04d}",
                "location_id": loc,
                "hire_date": hire.normalize(),
                "skill": rng.lognormal(0, 0.25),
            }
        )
        aid += 1
agents = pd.DataFrame(agent_rows)

# --------------------------------------------------------------------------
# 4. Applications (one row per loan application)
# --------------------------------------------------------------------------
days = pd.date_range(START, END, freq="D")
weekday_factor = {0: 1.00, 1: 1.00, 2: 1.00, 3: 1.15, 4: 0.60, 5: 1.20, 6: 1.05}  # Fri low, Thu/Sat high
month_factor = {1: 1.00, 2: 0.96, 3: 0.88, 4: 1.12, 5: 1.05, 6: 1.08}
type_product_p = {
    "Mall Kiosk": [0.55, 0.25, 0.05, 0.15],
    "Electronics Store": [0.45, 0.45, 0.02, 0.08],
    "Furniture Store": [0.05, 0.20, 0.70, 0.05],
}
BASE_APPS_PER_AGENT_DAY = 1.25

loc_index = {loc: i for i, loc in enumerate(loc_ids)}
records = []
for a in agents.itertuples(index=False):
    li = loc_index[a.location_id]
    ltype = locations.at[li, "location_type"]
    for d in days:
        if d < a.hire_date:
            continue
        tenure_m = (d - a.hire_date).days / 30.0
        ramp = min(1.0, 0.35 + 0.22 * tenure_m)
        lam = (
            BASE_APPS_PER_AGENT_DAY * traffic[li] * a.skill * ramp
            * weekday_factor[d.weekday()] * month_factor[d.month]
        )
        n = rng.poisson(lam)
        if n == 0:
            continue
        prod_idx = rng.choice(4, n, p=type_product_p[ltype])
        for p in prod_idx:
            prod = products.iloc[p]
            requested = float(np.round(rng.lognormal(np.log(prod.avg_ticket_egp), 0.35), -2))
            p_approve = np.clip(quality[li] + prod.approval_adj + 0.03 * min(tenure_m, 6) / 6 - 0.015, 0.05, 0.95)
            approved = rng.random() < p_approve
            disbursed = approved and (rng.random() > leakage[li])
            approved_amt = float(np.round(requested * rng.uniform(0.70, 1.00), -2)) if approved else 0.0
            records.append(
                (
                    d.date().isoformat(), a.agent_id, a.location_id, prod.product_id,
                    requested,
                    "Approved" if approved else "Rejected",
                    int(disbursed),
                    approved_amt if disbursed else 0.0,
                )
            )

applications = pd.DataFrame(
    records,
    columns=[
        "application_date", "agent_id", "location_id", "product_id",
        "requested_amount_egp", "decision", "is_disbursed", "disbursed_amount_egp",
    ],
)
applications.insert(0, "application_id", [f"APP{i:07d}" for i in range(1, len(applications) + 1)])

# --------------------------------------------------------------------------
# 5. Monthly disbursement targets per location
#    Planning uses a noisy estimate of the location's potential, so some
#    locations get targets that are too easy or too hard - like real life.
# --------------------------------------------------------------------------
agents_per_loc = agents.groupby("location_id").size().reindex(loc_ids).to_numpy()
avg_ticket_loc = np.array([
    np.dot(type_product_p[t], products["avg_ticket_egp"]) for t in locations["location_type"]
])
target_rows = []
for m in range(1, 7):
    days_in_m = days[days.month == m].size
    potential = (
        BASE_APPS_PER_AGENT_DAY * np.clip(traffic, 0.6, 1.8) * agents_per_loc
        * days_in_m * month_factor[m] * 0.93 * 0.64 * 0.92 * avg_ticket_loc * 0.85
    )
    noise = rng.normal(1.08, 0.12, N_LOCATIONS)
    target = np.round(potential * noise, -4)
    for loc, t in zip(loc_ids, target):
        target_rows.append({"month": f"2026-{m:02d}", "location_id": loc, "disbursement_target_egp": float(t)})
targets = pd.DataFrame(target_rows)

# --------------------------------------------------------------------------
# 6. Save
# --------------------------------------------------------------------------
agents_out = agents.drop(columns="skill")
tables = {
    "products": products.drop(columns="approval_adj"),
    "locations": locations.assign(opened_date=locations["opened_date"].dt.date.astype(str)),
    "agents": agents_out.assign(hire_date=agents_out["hire_date"].dt.date.astype(str)),
    "applications": applications,
    "targets": targets,
}
db_path = DATA / "lending.db"
db_path.unlink(missing_ok=True)
with sqlite3.connect(db_path) as con:
    for name, df in tables.items():
        df.to_csv(DATA / f"{name}.csv", index=False)
        df.to_sql(name, con, index=False)
        print(f"{name:<13} {len(df):>7,} rows")
print(f"\nSaved CSVs and SQLite database to {DATA}")
