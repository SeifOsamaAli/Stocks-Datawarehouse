"""
    Bronze Layer - Load JSON Into SQL Server (bronze_connection.py)

    Loads the raw JSON files produced by api.py (staged in the Dataset folder)
    into the Bronze.stocks_prices table in SQL Server.

    For every ticker/date combination found in the JSON files, checks whether a
    matching row already exists (by primary key: ticker + date):
        - If it doesn't exist yet, the row is inserted.
        - If it already exists, the row is updated with the newer values (upsert).

    Each file's rows are committed as a single all-or-nothing unit. Once a file's
    data is confirmed committed, its JSON file is deleted from Dataset, since it
    has served its purpose and the data now lives safely in the database.

    If a file fails partway through (e.g. connection drop, bad data), its changes
    are rolled back, the JSON file is kept, and the filename is added to a retry
    list. After the first pass over all files, any failures are retried up to
    max_retries times using the same loading function. Files still failing after
    that are logged as needing manual review rather than retried indefinitely.

    All events (success, failure, retries) are logged to a timestamped file in
    the Logs folder for auditing which files loaded successfully and which
    didn't, and why.
"""

from db_connection import create_connection
import os
import json
import logging
from datetime import datetime

# Logging & Datetime
now = datetime.now()
timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler(f'Logs/bronze_inserting_{timestamp}.log')

logger.addHandler(file_handler)
formatter = logging.Formatter(
    '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
)

file_handler.setFormatter(formatter)
logger.setLevel(logging.INFO)

# Connection & Dataabse
bronze_connection = create_connection()
cursor = bronze_connection.cursor()

# Os Making A List Of The Files Inside The Directory
folder_name = r"G:\Seko\Seif\Data Engineering\Stocks Project\Dataset"
files = os.listdir(folder_name)

# Initializing Lists Which Holds The Files
json_files = [file for file in files if file.endswith(".json")]


def bronze_inserting_data(files):
    failed_json = []
    for file in files:

        file_path = os.path.join(folder_name, file)
        try:
            with open(file_path, "r") as f:
                data = json.load(f)

            for ticker, dates_dict in data.items():
                for date, elements in dates_dict.items():

                    open_price = elements["1. open"]
                    high_price = elements["2. high"]
                    low_price = elements["3. low"]
                    close_price = elements["4. close"]
                    volume = elements["5. volume"]

                    # Checking Whether The (ticker + date) Were Inserted Before Or Not.
                    cursor.execute("SELECT ticker, date FROM Bronze.stocks_prices WHERE ticker = ? AND date = ?", (ticker, date))
                    exisiting_row = cursor.fetchone()

                    if exisiting_row == None:
                        cursor.execute("INSERT INTO Bronze.stocks_prices (ticker, date, open_price, high_price, low_price, close_price, volume) VALUES (?, ?, ?, ?, ?, ?, ?)", (ticker, date, open_price, high_price, low_price, close_price, volume))

                    else:
                        cursor.execute("UPDATE Bronze.stocks_prices SET open_price = ?, high_price = ?, low_price = ?, close_price = ?, volume =? WHERE ticker = ? AND date = ?", (open_price, high_price, low_price, close_price, volume, ticker, date))


            # Commit Only After ALL Rows In This File Succeed (All-Or-Nothing), So A Failure
            # Partway Through Never Leaves This File Half-Loaded In The Database.
            bronze_connection.commit()
            logger.info(f"Successfuly Inserted {ticker} Into The Database.")
            os.remove(file_path)

        except Exception as e:
            # If There Was An Error Inside A Specific File, It Will Rollback The Data Inserted And Add The Whole File Into The failed list
            bronze_connection.rollback()
            logger.error(f"There Were A Mistake Trying Inserting {file} Into The Database.")
            failed_json.append(file)

    return(failed_json)

went_wrong_json = bronze_inserting_data(json_files)

if len(went_wrong_json) >= 1:
    max_retries = 3
    number_of_retries = 0
    # Trying To Insert The Data For The Failed List, Trying 3 Times If It Still Doesn't Work That Mean It Might Be A Bug/Corrupted File
    while max_retries >= number_of_retries:
        went_wrong_json = bronze_inserting_data(went_wrong_json)
        if len(went_wrong_json) == 0:
            break

        number_of_retries += 1

if len(went_wrong_json) != 0:
    for file in went_wrong_json:
        logger.error(f"There Were A Problem While Trying Inserting {file}")

bronze_connection.close()