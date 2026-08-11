# Bronze Layer - Stock Data Extraction (`api.py`)

Fetches daily OHLCV (Open, High, Low, Close, Volume) data for 10 stock tickers from the [Alpha Vantage](https://www.alphavantage.co/) `TIME_SERIES_DAILY` API and saves each ticker's raw response as a separate JSON file. This is the first stage (Bronze / staging) of the Stock Market Data Warehouse pipeline — raw, untransformed data, captured exactly as the API returns it.

## What It Does

For each of the 10 tickers:
1. Calls the Alpha Vantage API for the last ~100 days of daily price data (`outputsize=compact`).
2. Validates the response and handles four possible outcomes (see [Error Handling](#error-handling--retry-behavior) below).
3. On success, saves the raw JSON response to its own file in `Dataset/`.
4. Logs every event (success, retry, failure) to a timestamped log file in `Logs/`.

## Setup

1. Install dependencies:
   ```
   pip install requests python-dotenv
   ```
2. Create a `.env` file in the project root with your Alpha Vantage API key:
   ```
   ALPHA_VANTAGE_API_KEY=your_key_here
   ```
3. Update `folder_name` in the script if you want the JSON output saved somewhere other than the default path.

## How To Run

```
python api.py
```

## Output

Each successful ticker produces one JSON file:

```
Dataset/{TICKER}_{RUN_TIMESTAMP}.json
```

Example: `Dataset/AAPL_2026-08-06_16-05-24.json`

Each file contains the raw API response for that ticker, keyed by symbol:

```json
{
  "AAPL": {
    "2026-08-05": {
      "1. open": "309.3600",
      "2. high": "311.7100",
      "3. low": "305.6700",
      "4. close": "311.0000",
      "5. volume": "49438763"
    },
    "2026-08-04": { "...": "..." }
  }
}
```

## Error Handling / Retry Behavior

Each ticker gets up to `max_retries` attempts (currently 2, meaning up to 3 total API calls per ticker in the worst case). The script distinguishes between temporary and permanent failures rather than treating every error the same way:

| Response | Retried? | Reasoning |
|---|---|---|
| Connection error / invalid JSON | Yes | Likely a transient network or server issue |
| Per-second rate limit hit | Yes (waits 12s) | Resolves quickly; a short wait clears it |
| Daily quota exhausted | No | Persists for 24 hours — retrying within the run is pointless |
| Invalid API key | No | Requires manual fix, not a transient issue |
| Invalid symbol | No | Requires manual fix, not a transient issue |
| Unrecognized error/info message | No | Unknown cause; safer to stop and flag for review than retry blindly |
| Unknown/unexpected response shape | Yes (once) | Could be a one-off fluke; capped retries prevent wasting calls if it isn't |

A short pause (`time.sleep(2)`) is also added after every successful call, proactively staying under Alpha Vantage's per-second rate limit before moving to the next ticker.

## Logging

Every run creates a fresh, timestamped log file: `Logs/bronze_{RUN_TIMESTAMP}.log`. It records, per ticker:
- Successful fetch and save
- Every retry attempt and why
- The exact reason for any failure (invalid key, invalid symbol, quota exhausted, unrecognized response, etc.)

This makes it possible to see at a glance which tickers succeeded or failed on any given run, and why, without re-reading the code.

## Known Limitations

- **10 tickers max** — Alpha Vantage's free tier allows 25 requests/day. With up to 3 calls per ticker in the worst case, 10 tickers keeps the daily budget safe; more tickers risk exhausting the quota before a full run completes.
- **~100 days of history per pull** — `outputsize=compact` returns only the most recent ~100 trading days, not full history.
- **No transformation** — this script only extracts and stages raw data. Type casting, cleaning, and validation happen downstream in the Silver layer.