"""Loads the CSV files into SQLite, runs every tagged query in sql/02_analysis_queries.sql,
and saves each result to results/q<N>.csv.   Usage:  python build_db.py"""
import re, sqlite3
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).parent
DB = ROOT / "manufacturing.db"
if DB.exists():
    DB.unlink()

con = sqlite3.connect(DB)
con.executescript((ROOT / "sql/01_schema.sql").read_text())

for table, csv in [("products", "products"), ("machines", "machines"),
                   ("production_log", "production_log"),
                   ("downtime_events", "downtime_events"),
                   ("inventory_monthly", "inventory_monthly")]:
    df = pd.read_csv(ROOT / "data" / f"{csv}.csv")
    df.to_sql(table, con, if_exists="append", index=False)
    print(f"loaded {len(df):>5} rows into {table}")

sql = (ROOT / "sql/02_analysis_queries.sql").read_text()
blocks = re.split(r"^-- (Q\d+)\s*$", sql, flags=re.M)[1:]
(ROOT / "results").mkdir(exist_ok=True)
for tag, body in zip(blocks[::2], blocks[1::2]):
    query = body.split("-- ====")[0].strip().rstrip(";")
    out = pd.read_sql_query(query, con)
    out.to_csv(ROOT / "results" / f"{tag.lower()}.csv", index=False)
    print(f"\n{tag}\n{out.to_string(index=False)}")
con.close()
