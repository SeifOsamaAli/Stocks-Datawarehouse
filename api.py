from dotenv import load_dotenv
load_dotenv()  # Load environment variables from .env file

import json
import os
import requests
import time
import logging
from datetime import datetime


API_KEY = os.environ["ALPHA_VANTAGE_API_KEY"] 
symbol = "AAPL"  

url = "https://www.alphavantage.co/query"

params = {
    "function": "TIME_SERIES_DAILY",
    "symbol": symbol,
    "outputsize": "compact",
    "apikey": API_KEY
}

now = datetime.now()
timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler(f'Logs/bronze_{timestamp}.log')
logger.addHandler(file_handler)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(name)s - %(message)s')
file_handler.setFormatter(formatter)
logger.setLevel(logging.INFO)

folder_name = r"G:\Seko\Seif\Data Engineering\Stocks Project\Dataset"
file_name = f"Stocks_{timestamp}.json"
file_path = os.path.join(folder_name, file_name)

max_retries = 2
number_of_retries = 0

while max_retries >= number_of_retries:
    response = requests.get(url, params=params)
    data = response.json()
    if "Error Message"in data:
        if "api key" in data["Error Message"].lower():
            logger.critical("Invalid API Key. Please check your API key and try again.")
            break

        elif "symbol" in data["Error Message"].lower():
            logger.warning("Invalid Symbol. Please check the symbol and try again.")
            break

    elif "Information" in data:
        if "premium" in data["Information"].lower():
            logger.critical("This Only Works For Premium Users. Please Upgrade Your Plan.")
            break

        else:
            number_of_retries += 1
            if number_of_retries >= max_retries:
                logger.warning("Max retries exceeded. Please try again later.")
                break

            else:
                logger.info("Rate limit exceeded, Please wait")
                time.sleep(12)

    elif "Time Series (Daily)" in data:
        time_series = data["Time Series (Daily)"]
        for date, daily_data in time_series.items():
            open_price = daily_data["1. open"]
            high_price = daily_data["2. high"]
            low_price = daily_data["3. low"]
            close_price = daily_data["4. close"]
            volume = daily_data["5. volume"]
        logger.info(f"Successfully fetched 100 days of data for {symbol} and saved to {file_path}")
        with open(file_path, "a") as f:
            json.dump(data, f, indent=4)
        
        break

    else:
        logger.warning(f"Unknown/Unexpected Response: {data}")
        break