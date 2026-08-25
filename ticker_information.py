from dotenv import load_dotenv
from db_connection import create_connection

gold_conncection = create_connection()
cursor = gold_conncection.cursor()

load_dotenv()

import json
import os
import requests
import time
import logging
from datetime import datetime


API_KEY = os.environ["ALPHA_VANTAGE_API_KEY1"]
symbols = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "META", "NVDA", "JPM", "V", "JNJ"]

url = "https://www.alphavantage.co/query"
params = {
    'function':"OVERVIEW",
    "symbol": symbols[0],
    "apikey": API_KEY
}


now = datetime.now()
timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler(f'Logs/Ticker_Information_{timestamp}.log')

logger.addHandler(file_handler)
formatter = logging.Formatter(
    '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
)

file_handler.setFormatter(formatter)
logger.setLevel(logging.INFO)

max_retries = 2

try:
    for symbol in symbols:
        number_of_retries = 0 
        params["symbol"] = symbol

        while max_retries >= number_of_retries:
            
                    
                try:
                    response = requests.get(url, params=params)
                    data = response.json()

                except (requests.exceptions.RequestException, json.JSONDecodeError) as e:
                    logger.error(f"Request/Parsing failed for {symbol}: {e}")
                    number_of_retries += 1
                    
                    if number_of_retries >= max_retries:
                        logger.warning(f"Max retries exceeded for {symbol} after request exception.")
                        break
                    else:
                        time.sleep(12)
                    continue

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

                #############################################3
                elif "Name" in data:
                    ticker = data["Symbol"]
                    company_name = data["Name"]
                    sector = data["Sector"]
                    industry = data["Industry"]
                    exchange = data["Exchange"]
                    currency = data["Currency"]
                    country = data["Country"]

                    # Checking Whether The (ticker) Were Inserted before Or Not.
                    cursor.execute("SELECT ticker FROM Gold.dim_ticker WHERE ticker = ?", (ticker,))
                    existing_row = cursor.fetchone()

                    if existing_row == None:
                        cursor.execute("INSERT INTO Gold.dim_ticker (ticker, company_name, sector, industry, exchange, currency, country) VALUES (?, ?, ?, ?, ?, ?, ?)", (ticker, company_name, sector, industry, exchange, currency, country))

                    else:
                        cursor.execute("UPDATE Gold.dim_ticker SET ticker = ?, company_name = ?, sector = ?, industry = ?, exchange = ?, currency = ?, country = ? WHERE ticker = ?", (ticker, company_name, sector, industry, exchange ,currency, country, ticker))

                    logger.info(f"Successfully fetched data for {symbol}")
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

finally:
    gold_conncection.commit()
    gold_conncection.close()