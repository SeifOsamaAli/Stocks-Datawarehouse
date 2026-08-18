"""
Bronze Layer - Stock Data Extraction (api.py)

Fetches daily OHLCV data for a list of stock tickers from the Alpha Vantage
TIME_SERIES_DAILY API and saves each ticker's raw response as a separate
JSON file (one file per ticker, per run) in the Dataset folder.

Includes retry logic and error handling for:
    - Connection/network errors (retried, likely transient)
    - Per-second rate limits (retried, resolves quickly)
    - Daily quota exhaustion (not retried, persists for 24 hours)
    - Invalid API key / invalid symbol (not retried, requires manual fix)
    - Unexpected/unknown API responses (retried once, may be a fluke)

All events (success, retries, failures) are logged to a timestamped file
in the Logs folder for auditing which tickers succeeded or failed, and why.
"""

from dotenv import load_dotenv

load_dotenv() # Load Environment Variables from .env file

import json
import os
import requests
import time
import logging
from datetime import datetime

  
API_KEY = os.environ["ALPHA_VANTAGE_API_KEY"]
symbols = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "META", "NVDA", "JPM", "V", "JNJ"]



# Ensuring Local Directories Exists To Prevent FileNotFoundError.
os.makedirs("Logs", exist_ok=True)
folder_name = r"G:\Seko\Seif\Data Engineering\Stocks Project\Dataset"
os.makedirs(folder_name, exist_ok=True)

url = "https://www.alphavantage.co/query"
params = {
    "function": "TIME_SERIES_DAILY",
    "symbol": symbols[0],
    "outputsize": "compact",
    "apikey": API_KEY
}


# Setting Up Logging
now = datetime.now()
timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler(f'Logs/API_Fetch/bronze_{timestamp}.log')

logger.addHandler(file_handler)
formatter = logging.Formatter(
    '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
)

file_handler.setFormatter(formatter)
logger.setLevel(logging.INFO)

max_retries = 2

for symbol in symbols:

    file_name = f"{symbol}_{timestamp}.json"
    file_path = os.path.join(folder_name, file_name)

    number_of_retries = 0
    params["symbol"] = symbol
    while max_retries >= number_of_retries:

        try:
            response = requests.get(url, params=params)
            data = response.json()

        # We Made It With Tries Because It Might Be A Connection Error, So Trying Again Can Fix It.
        except (requests.exceptions.RequestException, json.JSONDecodeError) as e:
            logger.error(f"Request/Parsing failed for {symbol}: {e}")
            number_of_retries += 1
            
            if number_of_retries >= max_retries:
                logger.warning(f"Max retries exceeded for {symbol} after request exception.")
                break
            else:
                time.sleep(12)
            continue

        # In Here We Just Exited The Loop Because No Matter How Many Tries It Won't Work.
        if "Error Message"in data:
            if "api key" in data["Error Message"].lower():
                logger.critical("Invalid API Key. Please check your API key and try again.")
                break

            elif "symbol" in data["Error Message"].lower():
                logger.warning("Invalid Symbol. Please check the symbol and try again.")
                break

            else:
                logger.warning(f"Unrecognized error message for {symbol}: {data['Error Message']}")
                break


        elif "Information" in data:
            # There Is A Daily Quota For How Many Calls We Can Get, So Regarding How Many Tries It Will Fail.
            if "remove" in data["Information"].lower():
                logger.critical(f"Daily rate limit exceeded for {symbol}. Wait 24 hours or upgrade.")
                break

            elif "1 request" in data["Information"].lower():
                number_of_retries += 1
                if number_of_retries >= max_retries:
                    logger.warning("Max retries exceeded. Please try again later.")
                    break

                # Waiting Here Because There Is A Rate Limit-Hit Per Second.
                else:
                    logger.info("Per-second rate limit hit, waiting before retry.")
                    time.sleep(12)
            else:
                logger.warning(f"Unrecognized Information message for {symbol}: {data['Information']}")
                break


        elif "Time Series (Daily)" in data:
            time_series = data["Time Series (Daily)"]
            with open(file_path, "w") as f:
                json.dump({symbol: time_series}, f, indent=4)
            logger.info(f"Successfully fetched 100 days of data for {symbol} and saved to {file_path}")
            # Pausing Proactively Between Successful Calls To Stay Under Alpha Vantage's Per-Second Rate Limit, Since We're About To Move To The Next Symbol.
            time.sleep(2)
            break

        else:
            logger.warning(f"Unknown/Unexpected Response for {symbol}: {data}")
            # We Don't Know The Issue So We Will Try Again. But If It Failed For 3 Times, So It's Likely Not A Connection Error Worth Trying.
            number_of_retries += 1
            if number_of_retries >= max_retries:
                logger.warning(f"Max retries exceeded for {symbol} after unknown response.")
                break
            else:
                time.sleep(12)