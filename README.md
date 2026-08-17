# Stock Market Data Warehouse

A Medallion Architecture (Bronze → Silver → Gold) data pipeline that pulls daily stock price data from the Alpha Vantage API, stages it raw, then progressively cleans and types it for analysis. Built as a hands-on portfolio project alongside the Data With Baraa data engineering roadmap.

Read this file for the big picture and the *why* behind design decisions. Each script also carries its own header comment for the *what* — open the script alongside this README for the full picture.

## Overview

| Layer | Purpose | Tables / Objects |
|---|---|---|
| Bronze | Raw, untyped staging — exactly what the API returned | `Bronze.stocks_prices` |
| Silver | Cleaned, typed, validated data ready for real use | `Silver.stocks_prices`, `Silver.load_log` |
| Gold | Not yet built | — |

## Pipeline Flow — Bronze

```
Alpha Vantage API
      │
      ▼
  api.py  ──────────►  Dataset/{TICKER}_{TIMESTAMP}.json   (raw staging files, one per ticker)
                              │
                              ▼
                    bronze_connect.py
                     (uses db_connection.py
                      to reach SQL Server)
                              │
                              ▼
                  Bronze.stocks_prices (SQL Server)
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
EXEC Silver.load_silver
  - reads Silver.load_log for this procedure's last successful run
  - filters Bronze to only rows where loaded_at > last_run
  - TRY_CAST's raw VARCHAR columns into real types
  - MERGE's into Silver.stocks_prices (insert new, update matching)
  - on success, advances Silver.load_log's last_run
        │
        ▼
Silver.stocks_prices
        │
        ▼
EXEC Silver.check_data_quality   (run manually, separately, after a load)
  - reports hard errors and soft flags, does not fix anything
```

`load_silver` and `check_data_quality` are two independent procedures, run separately. Nothing currently blocks `check_data_quality` from being skipped, and nothing currently automates either — both are triggered manually today.

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
4. Make sure SQL Server (`localhost\SQLEXPRESS`) is running. Run the DDL scripts in order:
   - `Scripts/init_database.sql` (creates the database and Bronze/Silver/Gold schemas)
   - `Scripts/Bronze/bronze_ddl.sql`
   - `Scripts/Silver/silver_ddl.sql`
   - `Scripts/Silver/silver_load_log_ddl.sql`
   - `Scripts/Silver/silver_proc.sql` (registers `Silver.load_silver`)
   - `Scripts/Silver/silver_check_data_quality.sql` (registers `Silver.check_data_quality`)
5. Update `folder_name` in `api.py` and `bronze_connect.py` if your `Dataset` folder lives somewhere other than the default path — both scripts must point to the same folder.

## Bronze Layer

### `api.py` — Extraction

Fetches ~100 days of daily price data for 10 tickers from Alpha Vantage and saves each as its own raw JSON file in `Dataset/`.

- **Output:** `Dataset/{TICKER}_{RUN_TIMESTAMP}.json`, one per ticker.
- **Error handling:** distinguishes transient failures (connection errors, per-second rate limits — retried) from permanent ones (invalid key, invalid symbol, daily quota exhausted — not retried), plus a capped single retry for unrecognized response shapes.
- **Ticker count capped at 10 by design:** with up to 3 API calls per ticker in the worst case (1 attempt + 2 retries) and a 25-calls/day free-tier limit, 10 tickers leaves enough headroom to survive a bad run without exhausting the daily quota. See Design Decisions below for the full math.
- **Logging:** every run writes to a fresh, timestamped `Logs/bronze_{RUN_TIMESTAMP}.log`.

### `db_connection.py` — Connection Utility

A single reusable function, `create_connection()`, returning a `pyodbc` connection to `Stocks_Datawarehouse` using Windows Authentication. Every other script imports from here rather than duplicating connection logic. Uses `TrustServerCertificate=yes`, which is a local-development convenience — see Design Decisions for the production risk this introduces if copied as-is.

### `bronze_connect.py` — Loading

Reads every `.json` file in `Dataset/`, and for each ticker/date row, upserts into `Bronze.stocks_prices` (insert if new, update if the primary key already exists). Every insert or update also stamps `loaded_at = GETDATE()`, which exists purely so `Silver.load_silver` can filter to recently changed rows later.

- **Atomicity:** each file's rows are committed as a single all-or-nothing unit. A failure partway through rolls back that file's changes entirely.
- **Cleanup:** a JSON file is only deleted after its data is confirmed committed — never before.
- **Retry logic:** failed files are collected and retried in a second pass, up to `max_retries` times, using the same loading function (no duplicated logic). Files still failing after that are logged as needing manual review.

### `bronze_ddl.sql` — `Bronze.stocks_prices`

Creates the table only if it doesn't already exist — deliberately non-destructive, unlike a typical drop-and-recreate DDL script. See Design Decisions for why.

```sql
Bronze.stocks_prices (
    ticker, date, open_price, high_price, low_price, close_price, volume  -- all VARCHAR(12)
    loaded_at DATETIME2 DEFAULT GETDATE() NOT NULL
    PRIMARY KEY (ticker, date)
)
```

All business columns are stored as raw `VARCHAR` — no transformation happens in Bronze. `loaded_at` is the one exception: pipeline metadata, not trading data, added specifically to support Silver's incremental filtering.

## Silver Layer

### `silver_ddl.sql` — `Silver.stocks_prices`

```sql
Silver.stocks_prices (
    ticker VARCHAR(12), date DATE,
    open_price, high_price, low_price, close_price DECIMAL(11,4),
    volume INT,
    PRIMARY KEY (ticker, date)
)
```

Unlike Bronze, this table drops and recreates on every rerun. That's safe here — see Design Decisions.

### `silver_load_log_ddl.sql` — `Silver.load_log`

A small control table that stores, per procedure, the timestamp of its last successful run. Exists solely to support `Silver.load_silver`'s incremental filtering — see Design Decisions for the full reasoning behind why this table exists at all, why it's a table rather than a variable, and why it's structured the way it is.

### `silver_proc.sql` — `Silver.load_silver`

The Bronze → Silver ETL. For each run:
1. Reads `Silver.load_log` for the last successful run timestamp.
2. Filters `Bronze.stocks_prices` to only rows where `loaded_at` is newer than that.
3. `TRY_CAST`s the filtered rows into Silver's real types (bad/uncastable values become `NULL` instead of failing the whole load).
4. `MERGE`s the result into `Silver.stocks_prices` — insert new `(ticker, date)` rows, update existing ones.
5. Reports row counts (inserted vs. updated) and load duration.
6. On success only, advances `Silver.load_log`'s timestamp for the next run.

Wrapped in `TRY/CATCH` for diagnostics on failure. See Design Decisions for why no explicit `ROLLBACK` is needed here, and why `MERGE` was used here despite being avoided in Bronze.

### `silver_check_data_quality.sql` — `Silver.check_data_quality`

A separate, read-only reporting procedure, run manually after a load. For each of three checks, reports both a count and the actual offending rows:

- **Hard error — Price Inversion:** `high_price < low_price`.
- **Hard error — Negative Value:** any of the 5 numeric columns is negative.
- **Soft flag — Zero Value:** any of the 5 numeric columns is exactly zero. This is flagged, not treated as an error — see Design Decisions for why zero is a legitimate market value.

Never modifies or fixes any data it finds. See Design Decisions for why.

## Design Decisions

**Why Bronze caps at 10 tickers.** `max_retries = 2` means up to 3 API calls per ticker in the worst case. 10 tickers × 3 = 30, already close to or over Alpha Vantage's 25-calls/day free-tier limit in a bad-luck scenario. More tickers would risk exhausting the daily quota before a full run even completes.

**Why `TrustServerCertificate=yes` is flagged as a risk.** It bypasses certificate validation errors caused by SQL Server's local, self-signed certificate — convenient for local development, but it means the connection can't verify it's really talking to the intended server. Production environments should use a properly chained certificate from a trusted CA to prevent man-in-the-middle attacks.

**Why `Bronze.stocks_prices` is non-destructive but `Silver.stocks_prices` is destructive.** The deciding question was: is the data recoverable if lost? Bronze isn't — `bronze_connect.py` deletes JSON files after a successful commit, and Alpha Vantage's `outputsize=compact` only ever returns the ~100 most recent trading days, so older accumulated history can't be re-pulled from the source if it's ever wiped. Silver, by contrast, is fully derived from Bronze — if it's ever dropped, running `EXEC Silver.load_silver` rebuilds it completely, with nothing lost. This is also why `bronze_ddl.sql`'s rerun behavior is a deliberate trade-off: a genuine future schema change (like widening a column) will silently do nothing if the script is rerun against an existing table. That's considered safer than the alternative (silently losing data), but it does mean real schema changes require a manual, deliberate `ALTER TABLE` — not a rerun of this script.

**Why `Silver.load_log` exists as its own table.** `Silver.load_silver` needs to know, on each run, when it last succeeded — so it can filter Bronze down to only rows changed since then, instead of rescanning the entire table every time. A SQL variable only exists for the lifetime of one execution and can't carry that fact forward to the next run; only a table persists between separate executions. This also isn't a fact about any single `(ticker, date)` row, so it doesn't belong bolted onto `Silver.stocks_prices` — it's a fact about the pipeline itself. `procedure_name` exists as a plain text label (not a special SQL concept) so this table could track more than one procedure's state in the future, rather than being permanently limited to tracking just `load_silver`. It stores a single overwritten row per procedure, not a growing history log, since the filter only ever needs the most recent value — the primary key is `(procedure_name)` alone, deliberately not composite with `last_run`, since a composite key would allow multiple rows per procedure and defeat the "one current value" design. The seed row (`'2000-01-01'`) is deliberately far older than any real `loaded_at`, so the very first filtered run doesn't accidentally exclude real data. This table is non-destructive by necessity — dropping it would silently reset the whole optimization back to "process everything."

**Why `Silver.load_silver` doesn't need an explicit `ROLLBACK`.** SQL Server treats a single statement as the smallest possible unit of atomicity — even though `MERGE` can insert some rows and update others in one execution, it's still one statement, and if any part of it fails partway through, SQL Server automatically undoes everything that statement had already done, without any `ROLLBACK` command being written. This is different from a script with several separate `INSERT`/`UPDATE` statements in sequence, where an earlier statement could succeed and commit before a later one fails, requiring a manual `ROLLBACK` to undo it. Because this procedure's data modification is entirely contained in one `MERGE`, that manual cleanup step isn't necessary. (Caveat: this guarantee has documented edge cases involving triggers in more complex setups — not a concern here, since there are no triggers and this runs single-threaded.)

**Why `MERGE` was used in Silver but avoided in Bronze.** Bronze's loader is a Python script looping through files, where a simple check-then-decide pattern was natural while still building SQL comfort; `MERGE`'s documented risk of subtle bugs is specifically in high-concurrency, multi-process scenarios, which didn't apply but still wasn't worth the added syntax complexity at the time. Silver's load, by contrast, is pure SQL with no Python loop involved at all, still runs single-threaded/sequential (no concurrency risk either way), and by this point in the project `MERGE`'s syntax was a reasonable thing to learn. Both decisions were re-evaluated against their actual context rather than treated as a fixed rule.

**Why quality checking is a separate procedure, not built into the load.** Embedding row-by-row accept/reject logic into `Silver.load_silver`'s `MERGE` would add real complexity to a job that's scoped to be cast-and-load only. Data quality reporting is treated as a distinct concern, run manually and separately.

**Why `check_data_quality` never auto-fixes anything it finds.** A garbage value (e.g. a negative price) can't be safely corrected by guessing — a `-150` could be a sign error, a decimal-placement error, or something else entirely. Silently "fixing" it risks producing a plausible-looking but wrong value, which is worse than an obviously-flagged one. The procedure only reports; correction is left to a human or a deliberate future business rule.

**Why zero values are flagged, not treated as errors.** Both stock price and trading volume can legitimately be exactly zero in the real world — a price of $0 can occur for a company near bankruptcy, and zero trading volume can occur from a trading halt, an order imbalance, or a court-supervised suspension. Only negative values are logically impossible and treated as hard errors.

**Why the Negative Value and Zero Value checks use temp tables instead of CTEs.** Both checks need their filtered row set twice — once for `COUNT(*)`, once for the detail `SELECT`. A CTE is scoped to only the single statement immediately following it, so it can't be reused across two separate statements. A temp table persists for the session/batch, so the filter logic is written once (`#negative_rows` / `#zero_rows`) and queried twice.

## Known Limitations

- **10 tickers, ~100 days of history per pull** — Alpha Vantage free-tier constraints.
- **No transformation in Bronze** — everything is raw `VARCHAR`. Type casting and validation are entirely Silver's responsibility.
- **`check_data_quality` reports only** — it never fixes anything it finds, by design (see Design Decisions).
- **No single automated pipeline yet** — `api.py`, `bronze_connect.py`, `Silver.load_silver`, and `Silver.check_data_quality` are all triggered manually today, in that order, one at a time. A scheduler/orchestration tool (e.g. Airflow) is planned but not yet built.
- **No gap detection** — `check_data_quality` doesn't check for missing trading days, since there's no reference trading calendar to compare against. Existing date gaps (weekends, holidays) are expected and not flagged.
- **Duplicate `(ticker, date)` rows are structurally impossible**, not something the load logic or quality checks need to guard against separately — the primary key on both `Bronze.stocks_prices` and `Silver.stocks_prices` already enforces this.
- **Gold layer not yet started.**