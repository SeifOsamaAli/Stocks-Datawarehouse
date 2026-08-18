"""
    Silver Layer - Pipeline Runner (run_silver_pipeline.py)

    Orchestrates the two Silver-layer stored procedures in sequence:
        1. EXEC Silver.load_silver — casts and merges new/changed rows from
           Bronze into Silver.stocks_prices (incremental, filtered by loaded_at).
        2. EXEC Silver.check_data_quality — runs hard-error and soft-flag checks
           against Silver.stocks_prices and logs the results.

    check_data_quality only runs if load_silver succeeds. If load_silver fails,
    there is no new/changed data to check, so the quality check is skipped and
    the failure is logged instead.

    This script does not call Bronze-layer code (api.py / bronze_connect.py).
    Bronze must be run separately, first. The full manual pipeline order is:
        1. api.py               (API -> JSON)
        2. bronze_connect.py    (JSON -> Bronze, upsert)
        3. run_silver_pipeline.py   (Bronze -> Silver, then quality checks)

    This script is written as a single importable/runnable unit (connection,
    logging, commit, and cleanup all self-contained) so it can later be called
    directly as an Airflow task without modification, once real orchestration
    is introduced.

    All events (success, failure per stage, quality check results) are logged
    to a timestamped file in Logs/Silver_Pipeline_Logs/ for auditing.

    Usage:
        python run_silver_pipeline.py
"""

from db_connection import create_connection
from datetime import datetime
import logging
import os
import pyodbc

# Ensuring Local Directories Exists To Prevent FileNotFoundError.
folder_name = r"G:\Seko\Seif\Data Engineering\Stocks Project\Logs\Silver_Pipeline_Logs"
os.makedirs(folder_name, exist_ok=True)


# Logging & Datetime
now = datetime.now()
timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler(f'{folder_name}/SilverPipeline_{timestamp}.log')

logger.addHandler(file_handler)
formatter = logging.Formatter(
    '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
)

file_handler.setFormatter(formatter)
logger.setLevel(logging.INFO)


# Connection & Database
silver_connection = create_connection()
cursor = silver_connection.cursor()


def Silver_Pipeline():
    start_time = datetime.now()
    try:
        try:
            cursor.execute("EXEC Silver.load_silver")
            result = cursor.fetchall()
            end_time = datetime.now()
            duration = end_time - start_time
            logger.info("Loading The Silver Layer.")
            if len(result) != 0:
                logger.info("Ran Successfully, Here's What Changed.")
                logger.info(f"{result}")

            else:
                logger.info("Ran Successfully, Nothing Has Changed")

            logger.info(f"Load Duration: {duration}")
            silver_connection.commit()
            logger.info("Silver Layer Was Loaded Successfully.")

        except pyodbc.Error as e:
            logger.error(f"Silver.load_silver failed: {e}")
            return

        try:
            cursor.execute("EXEC Silver.check_data_quality")
            logger.info("Data Quality Results.")

            count_wrong_prices = cursor.fetchall()
            cursor.nextset()
            row_wrong_prices = cursor.fetchall()
            cursor.nextset()

            if count_wrong_prices[0][0] != 0:
                logger.info(f"Number Of Wrong Prices: {count_wrong_prices}")
                logger.info(f"Rows: {row_wrong_prices}")

            else:
                logger.info("No Wrong Prices.")

            count_negative_prices = cursor.fetchall()
            cursor.nextset()
            row_negative_prices = cursor.fetchall()
            cursor.nextset()

            if count_negative_prices[0][0] != 0:
                logger.info(f"Number Of Negative Prices: {count_negative_prices}")
                logger.info(F"Rows: {row_negative_prices}")

            else:
                logger.info("No Negative Prices.")

            count_zero_prices = cursor.fetchall()
            cursor.nextset()
            row_zero_prices = cursor.fetchall()

            if count_zero_prices[0][0] != 0:
                logger.info(f"Number Of Zero Prices: {count_zero_prices}")
                logger.info(f"Rows: {row_zero_prices}")

            else:
                logger.info("No Zero Prices.")

        except pyodbc.Error as e:
            logger.error(f"Silver.check_data_quality: {e}")

    finally:
        silver_connection.close()

Silver_Pipeline()