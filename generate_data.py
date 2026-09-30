"""
Generates a SYNTHETIC manufacturing dataset for a fictional plant (2025).
All numbers are simulated for portfolio/learning purposes - not real company data.
Run:  python generate_data.py
"""
import numpy as np
import pandas as pd
from pathlib import Path

rng = np.random.default_rng(42)
OUT = Path(__file__).parent

# ---------- Reference tables ----------
products = pd.DataFrame([
    ("P100", "Steel Bracket",        "Fabricated"),
    ("P200", "Motor Housing",        "Machined"),
    ("P300", "Hydraulic Valve Body", "Machined"),
    ("P400", "Sensor Mount",         "Fabricated"),
    ("P500", "Gear Shaft",           "Machined"),
    ("P600", "Cover Plate",          "Stamped"),
], columns=["product_id", "product_name", "product_family"])

machines = pd.DataFrame([
    ("A-01", "A", "CNC Mill",   "P100", 520),
    ("A-02", "A", "CNC Lathe",  "P200", 430),
    ("A-03", "A", "CNC Lathe",  "P500", 400),
    ("B-01", "B", "Press Brake","P100", 560),
    ("B-02", "B", "Laser Cutter","P400", 610),
    ("B-03", "B", "Stamping Press","P600", 700),
    ("C-01", "C", "CNC Mill",   "P300", 380),
    ("C-02", "C", "CNC Mill",   "P300", 390),
    ("C-03", "C", "CNC Lathe",  "P200", 440),
    ("D-01", "D", "CNC Lathe",  "P500", 410),
    ("D-02", "D", "Stamping Press","P600", 690),
    ("D-03", "D", "Laser Cutter","P400", 600),
], columns=["machine_id", "line_id", "machine_type", "product_id", "daily_capacity"])

# base defect rate per machine (fraction of units)
base_defect = {"A-01":.014,"A-02":.016,"A-03":.015,"B-01":.019,"B-02":.017,"B-03":.021,
               "C-01":.030,"C-02":.034,"C-03":.022,"D-01":.016,"D-02":.018,"D-03":.017}
# month multipliers to plant a story: C-01/C-02 quality drifts upward from June to October
drift = {"C-02": {6:1.15,7:1.45,8:1.65,9:1.85,10:2.05,11:1.35,12:1.1},
         "C-01": {7:1.10,8:1.25,9:1.35,10:1.45,11:1.15}}

# ---------- Production log (weekdays only) ----------
days = pd.bdate_range("2025-01-01", "2025-12-31")
rows = []
rid = 1
for d in days:
    for m in machines.itertuples():
        util = rng.normal(0.88, 0.05)
        units = int(max(0, m.daily_capacity * np.clip(util, 0.6, 1.0)))
        rate = base_defect[m.machine_id] * drift.get(m.machine_id, {}).get(d.month, 1.0)
        defects = int(rng.binomial(units, min(rate, 0.5)))
        rows.append((rid, d.date().isoformat(), m.machine_id, m.product_id, units, defects))
        rid += 1
prod = pd.DataFrame(rows, columns=["record_id","production_date","machine_id","product_id",
                                    "units_produced","units_defective"])

# ---------- Downtime events ----------
reasons = ["Tool wear","Material jam","Sensor fault","Scheduled maintenance",
           "Changeover","Power/utility issue","Operator unavailable"]
base_w = np.array([.18,.14,.12,.22,.18,.06,.10])
c02_w  = np.array([.34,.10,.28,.10,.08,.05,.05])   # C-02: tool wear & sensor faults dominate
events = []
eid = 1
for m in machines.itertuples():
    for d in days:
        month = d.month
        lam = 0.10  # ~2.2 events/month per machine baseline (per weekday)
        if m.machine_id == "C-02":
            lam *= {7:5.0, 8:3.4, 9:3.2, 10:3.6, 6:2.0, 11:1.6}.get(month, 1.3)
        elif m.machine_id == "C-01":
            lam *= {7:1.8, 8:1.5, 9:1.5, 10:1.7}.get(month, 1.0)
        elif m.machine_id == "B-03" and month == 3:
            lam *= 1.8
        for _ in range(rng.poisson(lam)):
            w = c02_w if m.machine_id == "C-02" else base_w
            reason = rng.choice(reasons, p=w/w.sum())
            dur = float(np.clip(rng.lognormal(3.9 if m.machine_id == 'C-02' else 3.5, 0.6), 8, 360))
            if reason == "Scheduled maintenance": dur = float(np.clip(dur*0.9, 20, 120))
            events.append((eid, m.machine_id, d.date().isoformat(), round(dur), reason))
            eid += 1
down = pd.DataFrame(events, columns=["event_id","machine_id","event_date","duration_minutes","reason"])

# ---------- Month-end inventory (finished goods) ----------
inv_rows = []
reorder = {"P100":6000,"P200":5000,"P300":3000,"P400":5500,"P500":4500,"P600":7000}
on_hand = {"P100":9500,"P200":7800,"P300":5200,"P400":8500,"P500":6800,"P600":10500}
for mth in range(1, 13):
    for p in products.product_id:
        shift = rng.normal(0, 350)
        if p == "P300":
            shift += {6:-300,7:-650,8:-750,9:-700,10:-600,11:+100,12:+500}.get(mth, 0)
        on_hand[p] = max(1200, on_hand[p] + shift)
        inv_rows.append((f"2025-{mth:02d}", p, int(on_hand[p]), reorder[p]))
inv = pd.DataFrame(inv_rows, columns=["month","product_id","on_hand_units","reorder_point"])

products.to_csv(OUT/"products.csv", index=False)
machines.to_csv(OUT/"machines.csv", index=False)
prod.to_csv(OUT/"production_log.csv", index=False)
down.to_csv(OUT/"downtime_events.csv", index=False)
inv.to_csv(OUT/"inventory_monthly.csv", index=False)
print({k: len(v) for k, v in dict(products=products, machines=machines, production_log=prod,
                                   downtime_events=down, inventory=inv).items()})
