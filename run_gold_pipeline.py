"""
    Gold Layer - Pipeline Runner (run_gold_pipeline.py)

    Runs the Gold-layer stored procedure that populates
    Gold.fact_stock_prices from Silver.stocks_prices:

        EXEC Gold.load_gold — resolves each Silver row's ticker text into its
        surrogate key (ticker_id) via Gold.dim_ticker, then MERGEs new/changed
        rows into Gold.fact_stock_prices (incremental, filtered by
        Silver.stocks_prices.loaded_at against Pipeline.load_log).

    Before the MERGE runs, Gold.load_gold checks for any ticker in the
    filtered Silver scope that has no matching row in Gold.dim_ticker. That
    check's result is returned as its own result set (ahead of the MERGE's
    action_taken/row_count result set) so this script can log a warning if any
    tickers were skipped, rather than relying on the procedure's PRINT output,
    which pyodbc cannot capture.

    This script does not call ticker_information.py. Gold.dim_ticker is
    populated/maintained by that script separately, since ticker metadata
    changes rarely (unlike daily prices) and doesn't need to run on the same
    schedule as this load. The full manual pipeline order is:
        1. api.py                    (API -> JSON)
        2. bronze_connect.py         (JSON -> Bronze, upsert)
        3. run_silver_pipeline.py    (Bronze -> Silver, then quality checks)
        4. ticker_information.py     (OVERVIEW API -> Gold.dim_ticker, run rarely)
        5. run_gold_pipeline.py      (Silver -> Gold.fact_stock_prices)

    This script is written as a single importable/runnable unit (connection,
    logging, commit, and cleanup all self-contained) so it can later be called
    directly as an Airflow task without modification, once real orchestration
    is introduced.

    All events (success, failure, unmatched-ticker warnings) are logged to a
    timestamped file in Logs/Gold_Pipeline/ for auditing.

    Usage:
        python run_gold_pipeline.py
"""

from db_connection import create_connection
from datetime import datetime
import logging
import os
import pyodbc



# Ensuring Local Directories Exists To Prevent FileNotFoundError.
folder_name = r"G:\Seko\Seif\Data Engineering\Stocks Project\Logs\Gold_Pipeline"
os.makedirs(folder_name, exist_ok=True)


# Logging & Datetime
now = datetime.now()
timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler(f'{folder_name}/GoldPipeline_{timestamp}.log')

logger.addHandler(file_handler)
formatter = logging.Formatter(
    '%(asctime)s - %(levelname)s - %(name)s - %(message)s'
)

file_handler.setFormatter(formatter)
logger.setLevel(logging.INFO)


# Connection & Database
gold_connection = create_connection()
cursor = gold_connection.cursor()

def Gold_Pipeline():
    start_time = datetime.now()
    try:
    
        cursor.execute("EXEC Gold.load_gold")
        logger.info("Loading The Gold Layer")
        ticker_found_result = cursor.fetchall()

        if ticker_found_result[0][0] != None:
            logger.warning(f"Tickers in Silver Not Found in Dim_ticker: {ticker_found_result}")

        cursor.nextset()
        result = cursor.fetchall()
        end_time = datetime.now()
        load_duration = end_time - start_time

        logger.info(f"Loading Duration {load_duration}")
        logger.info(f"{result}")
        gold_connection.commit()

    except pyodbc.Error as e:
        logger.error(f"Gold.load_gold failed: {e}")
        return

    finally:
        gold_connection.close()


Gold_Pipeline()