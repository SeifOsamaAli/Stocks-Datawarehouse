# Bronze Layer

Raw data extraction and staging for the Stock Market Data Warehouse project. This is the first layer of the Medallion Architecture (Bronze → Silver → Gold) — data here is kept as close to the original source as possible, with no cleaning or transformation.

## Overview

The Bronze layer pulls daily OHLCV (Open, High, Low, Close, Volume) stock data for 10 tickers from the Alpha Vantage API, stages it as raw JSON files, then loads it into a SQL Server staging table. Three scripts work together to do this, each with a single responsibility:

| Script | Responsibility |
|---|---|
| `api.py` | Extracts data from the Alpha Vantage API, saves one raw JSON file per ticker |
| `db_connection.py` | Shared utility that opens a connection to the SQL Server database |
| `bronze_connection.py` | Loads the staged JSON files into `Bronze.stocks_prices`, then cleans up |

Read this file alongside the corresponding `.py` file open in your editor — each section below maps to inline comments and docstrings in that script.

## Pipeline Flow

```
Alpha Vantage API
      │
      ▼
  api.py  ──────────►  Dataset/{TICKER}_{TIMESTAMP}.json   (raw staging files, one per ticker)
                              │
                              ▼
                    bronze_connection.py
                     (uses db_connection.py
                      to reach SQL Server)
                              │
                              ▼
                  Bronze.stocks_prices (SQL Server)
                              │
                    (JSON file deleted once
                     its data is confirmed
                     committed to the database)
```

Each stage is independently runnable. You don't need to re-pull from the API to reload existing JSON files, and you don't need fresh JSON files to test the database connection.

## Setup

1. Install dependencies:
   ```
   pip install requests python-dotenv pyodbc
   ```
2. Install **ODBC Driver 18 for SQL Server** (a separate OS-level install from Microsoft, not a Python package).
3. Create a `.env` file in the project root:
   ```
   ALPHA_VANTAGE_API_KEY=your_key_here
   ```
4. Make sure SQL Server (`localhost\SQLEXPRESS`) is running, and the `Stocks_Datawarehouse` database and `Bronze.stocks_prices` table exist (see the DDL script for table creation).
5. Update `folder_name` in `api.py` and `bronze_connection.py` if your `Dataset` folder lives somewhere other than the default path — both scripts must point to the same folder.

## 1. `api.py` — Extraction

Fetches ~100 days of daily price data for each of the 10 tickers and saves each as its own raw JSON file in `Dataset/`.

**Output:** `Dataset/{TICKER}_{RUN_TIMESTAMP}.json`, one per ticker.

**Error handling:** distinguishes transient failures (connection errors, per-second rate limits — retried) from permanent ones (invalid key, invalid symbol, daily quota exhausted — not retried), plus a capped single retry for unrecognized response shapes. See the inline comments in the script for the reasoning behind each case.

**Ticker count:** capped at 10 by design. With up to 3 API calls per ticker in the worst case (1 attempt + 2 retries) and a 25-calls/day free-tier limit, 10 tickers leaves enough headroom to survive a bad run without exhausting the daily quota.

**Logging:** every run writes to a fresh, timestamped `Logs/bronze_{RUN_TIMESTAMP}.log`, recording each ticker's outcome and why.

## 2. `db_connection.py` — Connection Utility

A single reusable function, `create_connection()`, that opens a `pyodbc` connection to `Stocks_Datawarehouse` using Windows Authentication. Every other script imports from here rather than duplicating connection logic.

```python
from db_connection import create_connection

connection = create_connection()
cursor = connection.cursor()
```

Uses `TrustServerCertificate=yes` to work around SQL Server's local self-signed certificate — fine for local development, but a production setup should use a properly chained certificate instead (see the function's docstring for the full reasoning).

## 3. `bronze_connection.py` — Loading

Reads every `.json` file in `Dataset/`, and for each ticker/date row, checks whether it already exists in `Bronze.stocks_prices` (by primary key) — inserting new rows and updating existing ones (upsert). This makes the script safe to rerun: it will never create duplicates, and re-pulled data simply overwrites what's already there.

**Atomicity:** each file's rows are committed as a single all-or-nothing unit. A failure partway through a file rolls back that file's changes entirely, rather than leaving it half-loaded.

**Cleanup:** a JSON file is only deleted after its data is confirmed committed to the database — never before. This keeps `Dataset/` from growing unbounded over time while ensuring a JSON file always exists as a safety net until its data is safely stored.

**Retry logic:** files that fail (e.g. a dropped connection) are collected into a list rather than deleted, and retried in a second pass, up to `max_retries` times, using the same loading function (no duplicated logic). Files still failing after that are logged as needing manual review — see `bronze_inserting_data_{RUN_TIMESTAMP}.log`.

## Known Limitations

- 10 tickers, ~100 days of history per pull (Alpha Vantage free-tier constraints — see `api.py` section above).
- No transformation happens in Bronze — all values are stored as raw strings (`VARCHAR`), exactly as the API returns them. Type casting, validation, and cleaning are Silver-layer responsibilities.
- Automation (running this daily without manual intervention) is not yet implemented — currently run manually. A scheduler/orchestration tool (e.g. Airflow) is planned for a future iteration.