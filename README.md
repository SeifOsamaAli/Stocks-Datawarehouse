# Stock Market Data Warehouse

A Medallion Architecture (Bronze → Silver → Gold) data pipeline that pulls daily stock price data and company metadata from the Alpha Vantage API, stages it raw, progressively cleans and types it, and lands it in a business-ready star schema — queryable with plain `SELECT` statements by someone who just wants to check stock prices, no SQL expertise required.

This file is the single entry point for the whole project. Read it top to bottom for setup and the full picture; each `.sql`/`.py` file also carries its own header comment for quick reference while reading the code itself.

---

## Quick Start — Running This Locally, From Zero

This section assumes a fresh Windows machine with nothing installed. Follow it in order.

### 1. Install prerequisites

- **Python 3.10+** — [python.org](https://www.python.org/) or the Microsoft Store.
- **SQL Server Express** — free edition, from Microsoft. Note the instance name during install (this project assumes the default, giving a server name of `localhost\SQLEXPRESS`).
- **SQL Server Management Studio (SSMS)** — free, separate Microsoft download. Used to run the `.sql` scripts below.
- **ODBC Driver 18 for SQL Server** — a separate Microsoft download (not a Python package), required for Python to talk to SQL Server via `pyodbc`.
- **Git** (optional, if cloning rather than downloading the repo directly).

### 2. Get the project files

Clone or download the repository so you have the full folder structure locally (see [Project Structure](#project-structure) below).

### 3. Set up the Python environment

From the project root, in a terminal:

```
python -m venv .venv
.venv\Scripts\activate
pip install requests python-dotenv pyodbc
```

### 4. Create your `.env` file

In the project root, create a file named `.env` containing:

```
ALPHA_VANTAGE_API_KEY=your_first_api_key_here
ALPHA_VANTAGE_API_KEY_TICKER_INFO=your_second_api_key_here
DRIVER=ODBC Driver 18 for SQL Server
SERVER=localhost\SQLEXPRESS
DATABASE=Stocks_Datawarehouse
```

Get two free API keys from [alphavantage.co](https://www.alphavantage.co/support/#api-key) — two separate keys so the daily price pull (`api.py`) and the company-info pull (`ticker_information.py`) don't compete for the same 25-calls/day free-tier quota. Adjust `DRIVER`/`SERVER`/`DATABASE` if your own SQL Server setup differs from the defaults.

**Never commit `.env` to Git** — confirm it's listed in `.gitignore`.

### 5. Create the database and schemas

Open SSMS, connect to `localhost\SQLEXPRESS` with Windows Authentication, open `Scripts/init_database.sql`, and run it. This creates the `Stocks_Datawarehouse` database and the `Bronze`, `Silver`, `Gold`, and `Pipeline` schemas.

### 6. Run the DDL and procedure scripts, in this exact order

With `Stocks_Datawarehouse` selected as the active database in SSMS, open and run each of these in order — later scripts depend on objects created by earlier ones:

1. `Scripts/Pipeline/pipeline_load_log_ddl.sql`
2. `Scripts/Bronze/bronze_ddl.sql`
3. `Scripts/Silver/silver_ddl.sql`
4. `Scripts/Silver/silver_proc.sql` (registers `Silver.load_silver`)
5. `Scripts/Silver/check_data_quality.sql` (registers `Silver.check_data_quality`)
6. `Scripts/Gold/gold_dim_ticker_ddl.sql`
7. `Scripts/Gold/gold_fact_stock_prices_ddl.sql`
8. `Scripts/Gold/gold_proc.sql` (registers `Gold.load_gold`)

### 7. Run the pipeline — first time

From the project root, with the virtual environment active, run each in order, letting each finish before starting the next:

```
python api.py
python bronze_connect.py
python run_silver_pipeline.py
python ticker_information.py
python run_gold_pipeline.py
```

- `api.py` + `bronze_connect.py` — pull daily prices into Bronze.
- `run_silver_pipeline.py` — clean/type into Silver, then run data quality checks.
- `ticker_information.py` — pull company metadata into `Gold.dim_ticker`. **Run once**, or whenever metadata needs refreshing — not part of the daily cycle.
- `run_gold_pipeline.py` — load the Gold fact table from Silver.

After this, `Gold.dim_ticker` and `Gold.fact_stock_prices` hold business-ready data — queryable directly in SSMS, no casting or joining raw tables required.

### 8. Rerunning day-to-day

```
python api.py
python bronze_connect.py
python run_silver_pipeline.py
python run_gold_pipeline.py
```

(`ticker_information.py` skipped unless adding/refreshing a ticker.) Every script is incremental — reruns only process what's new or changed since the last successful run.

### Troubleshooting

- **`pyodbc.Error` on connect** — confirm SQL Server Express is running (Windows Services → "SQL Server (SQLEXPRESS)") and `.env`'s `SERVER` matches your actual instance name.
- **`ModuleNotFoundError`** — confirm the virtual environment is active and dependencies installed.
- **`Gold.load_gold` inserts 0 rows unexpectedly after manually rebuilding a table** — expected in one specific scenario, not a bug; see [Known Limitations](#known-limitations).

---

## Project Structure

```
Stocks Project/
├── api.py                          # Bronze extraction (API → JSON)
├── db_connection.py                # Shared DB connection utility (.env-driven)
├── bronze_connect.py               # Bronze loading (JSON → SQL, upsert, sets loaded_at)
├── run_silver_pipeline.py          # Orchestrates load_silver + check_data_quality
├── ticker_information.py           # Gold.dim_ticker loader (OVERVIEW API, upsert, run rarely)
├── run_gold_pipeline.py            # Orchestrates load_gold
├── Dataset/                        # Bronze staging JSON files (deleted after successful load)
├── Logs/
│   ├── bronze_{timestamp}.log
│   ├── bronze_inserting_{timestamp}.log
│   ├── Ticker_Information_{timestamp}.log
│   ├── Silver_Pipeline_Logs/
│   └── Gold_Pipeline/
├── Scripts/
│   ├── init_database.sql
│   ├── Bronze/
│   │   └── bronze_ddl.sql
│   ├── Silver/
│   │   ├── silver_ddl.sql
│   │   ├── silver_proc.sql
│   │   └── check_data_quality.sql
│   ├── Gold/
│   │   ├── gold_dim_ticker_ddl.sql
│   │   ├── gold_fact_stock_prices_ddl.sql
│   │   └── gold_proc.sql
│   └── Pipeline/
│       └── pipeline_load_log_ddl.sql
├── Docs/                           # Architecture diagrams (draw.io)
├── .env                            # API keys, DRIVER, SERVER, DATABASE — never committed
└── README.md                       # This file
```

---

## Overview

| Layer | Purpose | Tables / Objects |
|---|---|---|
| Bronze | Raw, untyped staging — exactly what the API returned | `Bronze.stocks_prices` |
| Silver | Cleaned, typed, validated data | `Silver.stocks_prices` |
| Gold | Business-ready star schema | `Gold.dim_ticker`, `Gold.fact_stock_prices` |
| Pipeline | Cross-layer control table | `Pipeline.load_log` |

## Pipeline Flow — Bronze

```
Alpha Vantage API (TIME_SERIES_DAILY)
      │
      ▼
  api.py  ──────────►  Dataset/{TICKER}_{TIMESTAMP}.json   (one raw file per ticker)
                              │
                              ▼
                    bronze_connect.py
                     (via db_connection.py)
                              │
                              ▼
                  Bronze.stocks_prices
                    every insert/update stamps
                    loaded_at = GETDATE()
                              │
                    (JSON file deleted once
                     its data is confirmed
                     committed to the database)
```

## Pipeline Flow — Silver

```
Bronze.stocks_prices
        │
        ▼
run_silver_pipeline.py
  ├─► EXEC Silver.load_silver
  │     - reads Pipeline.load_log for load_silver's last successful run
  │     - filters Bronze to rows where loaded_at > last_run
  │     - TRY_CASTs raw VARCHAR into real types
  │     - MERGEs into Silver.stocks_prices (insert new, update matching)
  │     - on success, advances Pipeline.load_log
  │
  └─► (if load_silver succeeds) EXEC Silver.check_data_quality
        - reports hard errors and soft flags, fixes nothing
        │
        ▼
Silver.stocks_prices
```

## Pipeline Flow — `ticker_information.py`

```
Alpha Vantage OVERVIEW API (separate API key)
        │
        ▼
ticker_information.py
  - one call per ticker, upsert
        │
        ▼
Gold.dim_ticker
```

Run rarely — once per new ticker, or on a metadata refresh. Not part of the daily cycle.

## Pipeline Flow — Gold

```
Silver.stocks_prices ──────┐
                            │
Gold.dim_ticker ────────────┤
                            ▼
                run_gold_pipeline.py
                  └─► EXEC Gold.load_gold
                        - reads Pipeline.load_log for load_gold's last run
                        - filters Silver to rows where loaded_at > last_run
                        - flags Silver tickers missing from Dim_ticker (visibility warning)
                        - MERGEs into Gold.fact_stock_prices via INNER JOIN on ticker
                        - on success, advances Pipeline.load_log
                            │
                            ▼
                Gold.fact_stock_prices
```

`run_silver_pipeline.py` and `run_gold_pipeline.py` are independently triggered — nothing currently chains Bronze → Silver → Gold automatically in one command (see Known Limitations).

---

## Bronze Layer

### `api.py` — Extraction

Fetches ~100 days of daily price data for 10 tickers from Alpha Vantage, saving each as its own raw JSON file in `Dataset/`.

- **Error handling** distinguishes transient failures (connection errors, per-second rate limits — retried) from permanent ones (invalid key/symbol, daily quota exhausted — not retried), plus a capped single retry for unrecognized response shapes.
- **10-ticker cap is deliberate** — see Design Decisions.
- Fresh, timestamped log per run in `Logs/`.

### `db_connection.py` — Connection Utility

Single reusable `create_connection()` function, returning a `pyodbc` connection to `Stocks_Datawarehouse` via Windows Authentication. `DRIVER`/`SERVER`/`DATABASE` are read from `.env`; `Trusted_Connection`/`Encrypt` are hardcoded — see Design Decisions for why the split.

### `bronze_connect.py` — Loading

Reads every `.json` file in `Dataset/`, upserting each ticker/date row into `Bronze.stocks_prices`. Every insert/update stamps `loaded_at = GETDATE()`, which exists purely to support Silver's incremental filtering.

- **Atomicity**: each file's rows commit as one all-or-nothing unit.
- **Cleanup**: a JSON file is only deleted after its data is confirmed committed.
- **Retry logic**: failed files are retried in a second pass (capped), using the same reusable loading function.

### `Bronze.stocks_prices` (`bronze_ddl.sql`)

```sql
Bronze.stocks_prices (
    ticker, date, open_price, high_price, low_price, close_price, volume   -- all VARCHAR(12)
    loaded_at DATETIME2 DEFAULT GETDATE() NOT NULL
    PRIMARY KEY (ticker, date)
)
```

Non-destructive (create-if-missing) — see Design Decisions. All business columns are raw `VARCHAR`; no transformation happens in Bronze.

---

## Silver Layer

### `Silver.stocks_prices` (`silver_ddl.sql`)

```sql
Silver.stocks_prices (
    ticker VARCHAR(12), date DATE,
    open_price, high_price, low_price, close_price DECIMAL(11,4),
    volume INT,
    loaded_at DATETIME2 DEFAULT GETDATE() NOT NULL,
    PRIMARY KEY (ticker, date)
)
```

Destructive (drop-and-recreate) — safe since every row is fully derived from Bronze. Also resets `Pipeline.load_log`'s `load_silver` entry on rebuild — see Design Decisions.

### `Silver.load_silver` (`silver_proc.sql`)

1. Reads `Pipeline.load_log` for the last successful run.
2. Filters Bronze to rows changed since then.
3. `TRY_CAST`s into real types (bad values become `NULL`, not a failed load).
4. `MERGE`s into `Silver.stocks_prices`.
5. Reports insert/update counts and duration.
6. On success, advances `Pipeline.load_log`.

No explicit `ROLLBACK` needed — see Design Decisions.

### `Silver.check_data_quality` (`check_data_quality.sql`)

Read-only reporting procedure, run after a load. Three checks, each reporting a count and the offending rows:

- **Hard error** — Price Inversion (`high_price < low_price`)
- **Hard error** — Negative Value (any of the 5 numeric columns negative)
- **Soft flag** — Zero Value (any of the 5 numeric columns exactly zero — valid, not an error; see Design Decisions)

Never modifies or fixes anything it finds.

### `run_silver_pipeline.py`

Python orchestrator: calls `Silver.load_silver`; if it fails, logs the error and stops (no point checking quality on a load that didn't happen). If it succeeds, calls `Silver.check_data_quality`, retrieves all six of its result sets via `fetchall()`/`nextset()`, and logs everything. Commits and closes the connection on every exit path.

---

## Gold Layer

### Business framing

Designed for "the normal person who wants to check stock prices to decide which one to buy" — not a SQL-literate analyst. This drove several decisions: no derived/computed columns (day-over-day change, moving averages — these stay query-time, not stored), no pipeline metadata bolted onto the fact table (reuses `Pipeline.load_log` instead), and a full BI/dashboard front-end is explicitly deferred until Gold and real orchestration both exist.

### `Gold.dim_ticker` (`gold_dim_ticker_ddl.sql`)

```sql
Gold.dim_ticker (
    ticker_id     INT IDENTITY(1,1) PRIMARY KEY,
    ticker        VARCHAR(12) UNIQUE NOT NULL,
    company_name  VARCHAR(100) NOT NULL,
    sector, industry   VARCHAR(100),
    exchange      VARCHAR(10),
    currency      VARCHAR(3),
    country       VARCHAR(50)
)
```

Non-destructive — this data costs real API calls to rebuild. `ticker_id` is a surrogate key — see Design Decisions.

### `ticker_information.py`

Pulls company metadata from Alpha Vantage's `OVERVIEW` endpoint, one call per ticker, using a separate API key. Upserts directly into `Gold.dim_ticker` per ticker — no JSON staging, unlike Bronze; see Design Decisions for why that's the right call here specifically.

### `Gold.fact_stock_prices` (`gold_fact_stock_prices_ddl.sql`)

```sql
Gold.fact_stock_prices (
    ticker_id    INT NOT NULL,
    date         DATE NOT NULL,
    open_price, high_price, low_price, close_price   DECIMAL(11,4),
    volume       INT,
    PRIMARY KEY (ticker_id, date),
    FOREIGN KEY (ticker_id) REFERENCES Gold.dim_ticker (ticker_id)
)
```

Destructive — fully recomputable from Silver at zero cost. Also resets `Pipeline.load_log`'s `load_gold` entry on rebuild. The foreign key means a ticker's prices can't load until that ticker exists in `Dim_ticker`.

### `Gold.load_gold` (`gold_proc.sql`)

1. Reads `Pipeline.load_log` for the last successful run.
2. Checks for Silver tickers missing from `Dim_ticker` and surfaces them as a warning (always returned as its own result set, so Python can reliably retrieve it).
3. `MERGE`s Silver into `Gold.fact_stock_prices`, joining to `Dim_ticker` for the surrogate key, using `INNER JOIN`.
4. Reports counts and duration; advances `Pipeline.load_log` on success.

### `run_gold_pipeline.py`

Simpler than `run_silver_pipeline.py` — calls a single procedure. `try/except/finally`, guaranteeing `close()` on every exit path. Fetches the missing-tickers result set, then the insert/update counts, logs both, commits. Deliberately doesn't call `ticker_information.py` — see Design Decisions.

### `Pipeline.load_log` (`pipeline_load_log_ddl.sql`)

Shared control table — one row per tracked procedure (`load_silver`, `load_gold`), storing each one's last successful run. Originally `Silver.load_log`, generalized and moved to its own schema once Gold needed the same mechanism.

---

## Design Decisions

This section holds every non-obvious "why" behind the project — in-file comments stay short and point here rather than repeating this reasoning inline.

**Why Bronze caps at 10 tickers.** `max_retries = 2` means up to 3 API calls per ticker worst-case. 10 × 3 = 30, already at or past Alpha Vantage's 25-calls/day free-tier limit in a bad run. More tickers risk exhausting quota before a full run even completes.

**Why `TrustServerCertificate=yes` is a flagged risk, not a free pass.** It bypasses validation of SQL Server's local, self-signed certificate — fine for local development, but it means the connection can't verify it's really talking to the intended server. Production should use a properly chained CA certificate to prevent man-in-the-middle attacks.

**Why `DRIVER`/`SERVER`/`DATABASE` live in `.env` but `Trusted_Connection`/`Encrypt` stay hardcoded.** The first three are machine-specific facts (a different computer can have a different instance name or driver version) — same reasoning that already put the API key in `.env`. The latter two are fixed security/authentication policy decisions, not machine facts; keeping them in code means changing them requires the same scrutiny as any other code change, rather than a silent config edit.

**Why `Bronze.stocks_prices` is non-destructive but `Silver.stocks_prices`/`Gold.fact_stock_prices` are destructive.** The deciding question throughout: is this data recoverable if lost? Bronze isn't — JSON files are deleted after a successful commit, and Alpha Vantage's `outputsize=compact` only returns the ~100 most recent trading days, so accumulated history can't be re-pulled from the source. Silver and the Gold fact table are both fully derived from an upstream layer and can be rebuilt from scratch at zero real cost by rerunning their load procedure. `Gold.dim_ticker` breaks this pattern in the other direction — it's non-destructive despite being "downstream," because rebuilding it costs real API calls (via `ticker_information.py`), not because of its position in the pipeline.

**Why `Pipeline.load_log` exists as a real table, rather than comparing timestamps between layers directly.** Two alternatives were seriously considered and rejected. Comparing `loaded_at` values across two tables directly doesn't reduce the work being filtered (still requires scanning both full tables), a plain join would silently exclude brand-new rows with no counterpart downstream yet, and it conflates "did this row change" with a comparison that never actually defines what "recent" means for the procedure's own baseline. A `MAX(loaded_at)`-style column alone can't distinguish "the procedure ran and found nothing new" from "the procedure never ran" — both leave that value unchanged. Only a table recording the procedure's own last successful run, independent of row-level data, solves the actual problem. It lives in its own `Pipeline` schema (moved there via `ALTER SCHEMA ... TRANSFER`) because it's shared infrastructure, not something Silver owns exclusively.

**Why `Silver.load_silver`/`Gold.load_gold` don't need an explicit `ROLLBACK`.** SQL Server treats a single statement as the smallest unit of atomicity. `MERGE` is one statement, even though it can insert some rows and update others — if any part fails partway through, SQL Server automatically undoes everything that statement had already done, with no `ROLLBACK` command needed. This differs from a script with several separate `INSERT`/`UPDATE` statements in sequence, where an earlier one could commit before a later one fails, genuinely requiring a manual `ROLLBACK`. (Caveat: this guarantee has documented edge cases involving triggers in more complex setups — not a concern here, with no triggers and single-threaded execution.)

**Why `MERGE` was used in Silver and Gold but avoided in Bronze.** Bronze's loader is a Python script looping through files, where a simple check-then-decide pattern was natural while SQL comfort was still being built; `MERGE`'s documented risk is specifically in high-concurrency, multi-process scenarios, which never applied here but still wasn't worth the added syntax complexity at the time. Silver and Gold's loads are pure SQL with no Python loop at all, still run single-threaded, and by that point `MERGE` was a reasonable, deliberate thing to learn. Each decision was evaluated against its actual context rather than applied as a fixed rule.

**Why quality checking is a separate procedure, not built into the load.** Embedding row-by-row accept/reject logic into `load_silver`'s `MERGE` would add real complexity to a job scoped as cast-and-load only. Reporting is treated as a distinct, separately-run concern.

**Why `check_data_quality` never fixes anything it finds.** A garbage value (e.g. a negative price) can't be safely corrected by guessing — it could be a sign error, a decimal-placement error, or something else entirely. Silently "fixing" it risks a plausible-looking but wrong value, worse than one that's obviously flagged. Correction is left to a human or a deliberate future business rule.

**Why zero values are flagged, not treated as hard errors.** Both price and volume can legitimately be exactly zero — a price of $0 near bankruptcy, zero volume from a trading halt, an order imbalance, or a court-supervised suspension. Only negative values are logically impossible.

**Why the negative-value and zero-value checks use temp tables instead of CTEs.** Both checks need their filtered row set twice (once for `COUNT(*)`, once for the detail rows). A CTE is scoped to only the single statement immediately following it and can't be reused across two separate statements; a temp table persists for the session, so the filter logic is written once and queried twice.

**Why a surrogate key (`ticker_id`), not the ticker symbol itself, is the fact table's join key.** If a ticker were ever renamed, a text-based key would mean updating every historical fact row referencing it. With a surrogate key, a rename only requires updating one row in `Dim_ticker` — every fact row keeps pointing at the same `ticker_id`, unaffected. `ticker` still carries a `UNIQUE` constraint for fast lookup by symbol.

**Why the fact table has no surrogate key of its own (e.g. `price_id`).** `(ticker_id, date)` already uniquely identifies every row, and nothing else would ever need to reference one individual fact row — an extra identity column would add complexity with no real benefit.

**Why derived metrics (day-over-day change, moving averages, price range) aren't stored columns.** They're arithmetic on data already present. Storing them risks staleness if an underlying price is ever corrected — the same don't-silently-trust-a-derived-value principle behind `check_data_quality` never auto-fixing anything. They remain query-time calculations, and are a candidate Future Modification rather than a warehouse requirement.

**Why there's no metadata/tracking column on `Gold.fact_stock_prices`.** Same reasoning as `Pipeline.load_log`'s existence generally — knowing when a procedure last ran is a fact about the procedure, not about any individual row. `Pipeline.load_log` is reused for `load_gold` rather than adding a column or a second log table.

**Why `Gold.load_gold` uses `INNER JOIN` against `Dim_ticker`, plus an explicit visibility check.** A `LEFT JOIN` would produce `NULL` `ticker_id`s for any Silver ticker not yet in `Dim_ticker` — but the fact table's foreign key would reject those rows anyway, just less predictably. `INNER JOIN` cleanly excludes them instead. Because that alone would silently drop unmatched tickers with no error, a separate check runs first (`NOT EXISTS`, chosen over `NOT IN` for its well-known `NULL`-poisoning trap, combined with `STRING_AGG` rather than a row-by-row `CURSOR`, since set-based operations are the more idiomatic T-SQL choice) and surfaces anything missing as an explicit warning.

**Why the missing-tickers value is always its own result set, even when empty.** `PRINT` output isn't reliably retrievable from Python via `pyodbc` — a real, confirmed limitation. An unconditional `SELECT @Missing_tickers AS missing_tickers;`, always present regardless of whether anything was found, is simpler and more predictable for Python's `fetchall()`/`nextset()` sequence to consume than a result set whose presence varies by data.

**Why rebuilding a destructive table also resets its `Pipeline.load_log` entry.** A real incident: rebuilding `Gold.fact_stock_prices` wiped its data, but `load_gold`'s log entry still held its previous timestamp, so the next run concluded (correctly by its own logic) that nothing had changed and inserted zero rows into a now-empty table. Alternatives considered: relying on memory to rerun manually (rejected — this is exactly the failure that happened); checking `IF NOT EXISTS (SELECT 1 FROM target)` at load time (rejected — only catches full wipes, doesn't address the root cause); comparing row counts between layers (rejected — Silver and Gold aren't expected to match even when healthy, since the `INNER JOIN` deliberately excludes unmatched tickers, so this would false-positive constantly). The chosen fix resets the log entry inside the destructive DDL script itself, immediately after the drop — applied identically to `silver_ddl.sql` and `gold_fact_stock_prices_ddl.sql`. Deliberately only handles full wipes, not partial row loss, which is accepted as a documented limitation rather than solved, since a full rebuild is a rare, manual action.

**Why a Silver rebuild makes the next Gold load do more work than usual without producing wrong data.** Resetting `load_silver`'s log entry causes the next Silver run to reprocess all of Bronze, refreshing `loaded_at` on every Silver row — including ones whose values didn't actually change. That makes the next `Gold.load_gold` run see all of Silver as "changed," producing mostly `UPDATE`s rather than `INSERT`s. Each `UPDATE` writes the same values already present, so the final data stays correct; only the amount of work done for that one run increases.

**Why `ticker_information.py` doesn't stage to JSON files the way Bronze does.** Bronze's per-ticker file exists because a single run processes ~100 rows per ticker across many dates, where multi-row atomicity and retry genuinely matter and losing a response would waste real quota. `OVERVIEW` returns exactly one row per ticker — each fetch-and-upsert is already a small, independent unit with nothing multi-row to protect, and re-fetching one failed ticker costs a single call. A direct per-ticker upsert inside the loop, no intermediate file, is the simpler correct choice for this differently-shaped problem.

**Why `run_gold_pipeline.py` doesn't call `ticker_information.py`, and `run_silver_pipeline.py` doesn't call `bronze_connect.py`.** These run on genuinely different cadences — metadata changes rarely, prices change daily. Chaining them via Python calls would blur that distinction. The intended path for wiring them together is the future orchestration layer, where each becomes an independent task with dependencies declared explicitly rather than hardcoded in Python.

**Why script names aren't unified under one naming convention.** `run_silver_pipeline.py`/`run_gold_pipeline.py` genuinely orchestrate multiple stored procedures with branching logic between them. `bronze_connect.py`/`ticker_information.py` are single-purpose, single-job scripts with no such orchestration. Forcing uniform names would erase a real, useful distinction the current names already communicate.

---

## Known Limitations

- **10 tickers, ~100 days of history per Bronze pull** — Alpha Vantage free-tier constraints.
- **No transformation in Bronze** — everything is raw `VARCHAR`; typing and validation are entirely Silver's job.
- **`check_data_quality` reports only** — never fixes anything it finds, by design.
- **Ticker renames aren't automatically detected.** The surrogate key makes propagating a rename cheap, but recognizing that a new symbol represents the same company is a business judgment the database can't make on its own. Today this needs manual reconciliation, or the renamed ticker silently becomes a new, disconnected `ticker_id`.
- **`Pipeline.load_log`'s reset-on-rebuild only handles full table wipes, not partial data loss.**
- **No single automated pipeline yet.** All five scripts (`api.py`, `bronze_connect.py`, `run_silver_pipeline.py`, `ticker_information.py`, `run_gold_pipeline.py`) are triggered manually today, in order. A scheduler/orchestration tool (e.g. Airflow) is the next real milestone once documentation is complete — every script is already self-contained (own connection, logging, commit, cleanup) specifically so it can become a drop-in task later.
- **`ticker_information.py` is not automated** — run manually when adding a ticker or refreshing metadata.
- **No gap detection** — no reference trading calendar exists to check for missing trading days; existing gaps (weekends, holidays) are expected, not flagged.
- **Duplicate `(ticker, date)` / `(ticker_id, date)` rows are structurally impossible**, enforced by primary keys at every layer — not something load logic or quality checks need to separately guard against.
- **No BI or dashboard front-end.** Deliberately deferred until Gold and orchestration both exist, so data engineering scope doesn't blur into front-end scope prematurely.

## Future Modifications (not built, under consideration)

- **Ticker-reconciliation flagging**, if ticker discovery is ever automated (e.g. a `yfinance` integration): a log warning like "new ticker X not found in Dim_ticker — auto-inserting as new," so a human can catch a disguised rename before it's silently treated as brand new.
- **Query-time views or procedures for derived metrics** — day-over-day % change, price range, moving averages.
- **A second data source (`yfinance`)** — a named scalability goal, not yet scoped.
- **Real orchestration (Airflow)** — the next concrete milestone once documentation wraps up.