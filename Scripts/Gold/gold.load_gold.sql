/*
============================================
Stored Procedure: Load Gold Layer (Silver -> Gold)
============================================

Script Purpose:
	This Stored Procedure Performs The ETL (Extract, Transform, Load) Process To
	Populate 'Gold.fact_stock_prices' From 'Silver.stocks_prices', Resolving Each
	Row's Ticker Text Into Its Corresponding Surrogate Key (ticker_id) Via
	'Gold.dim_ticker'.

	Actions Performed:
		- Filters Silver To Only Rows Where 'loaded_at' Is Newer Than This
		  Procedure's Last Successful Run (Read From Pipeline.load_log), Instead
		  Of Rescanning Silver's Entire History On Every Run. This Keeps The Load
		  Fast As Silver Grows, Since Only New Or Recently Corrected Rows Are
		  Considered.
		- Before Loading, Checks Whether Any Ticker In That Filtered Set Has No
		  Matching Row In Gold.dim_ticker. If So, Prints A Warning Listing The
		  Unmatched Tickers By Name — These Rows Are Silently Excluded From The
		  Load By The INNER JOIN Below, So This Warning Is The Only Visibility
		  Into Data That Was Skipped. A Missing Match Typically Means
		  ticker_information.py Has Not Yet Been Run For That Ticker.
		- Joins Silver.stocks_prices To Gold.dim_ticker On Ticker Text (INNER
		  JOIN) To Resolve ticker_id. Any Silver Row Whose Ticker Has No Match In
		  Dim_ticker Is Excluded From The Load Entirely (See Warning Above) Rather
		  Than Inserted With A NULL Foreign Key, Which The FOREIGN KEY Constraint
		  On Gold.fact_stock_prices Would Reject Regardless.
		- Uses MERGE To Insert New (ticker_id, date) Rows And Update Existing
		  Ones, Based On That Filtered, Joined Set.
		- Wrapped In TRY/CATCH: Any Failure Triggers A ROLLBACK, Prints Diagnostic
		  Error Information, And Re-Throws The Original Error (Via THROW) So Any
		  Calling Code (E.g. Python/pyodbc) Can Actually Detect The Failure.
		- Reports Load Results (Row Counts Per Action: INSERT / UPDATE) And Total
		  Load Duration (Duration Includes The Unmatched-Ticker Check, Since Both
		  Run As Part Of The Same Timed Operation).
		- On A Successful Run Only, Updates Pipeline.load_log's 'last_run'
		  Timestamp For procedure_name = 'load_gold', So The Next Run's Filter
		  Advances Correctly. If The Load Fails, 'last_run' Is Left Untouched, So
		  Nothing Is Skipped Next Time.

Dependencies:
	Requires 'Silver.stocks_prices' To Have A 'loaded_at' Column (Set By
	Silver.load_silver), 'Gold.dim_ticker' To Be Populated (Via
	ticker_information.py) For Any Ticker Expected To Appear In The Fact Table,
	And 'Pipeline.load_log' To Exist With A Seeded Row For
	procedure_name = 'load_gold'.

Known Limitation:
	Ticker Renames Are Not Detected Automatically. If A Ticker Symbol Changes,
	It Will Appear As An Unmatched Ticker (See Warning Above) Until
	Gold.dim_ticker Is Manually Updated To Reflect The New Symbol Against The
	Existing ticker_id, Rather Than Being Treated As A Brand New Ticker.

Parameters:
	None.

Usage Example:
	EXEC Gold.load_gold;
*/

CREATE OR ALTER PROCEDURE Gold.load_gold AS 
SET NOCOUNT ON;
BEGIN

    -- Creating Variables
	DECLARE @Start_load DATETIME, @End_load DATETIME
    DECLARE @Merge_results TABLE (action_taken VARCHAR(10)); 
    DECLARE @Last_run DATETIME2
    DECLARE @Missing_tickers VARCHAR(MAX)

    SET @Last_run = (SELECT last_run FROM Pipeline.load_log WHERE procedure_name = 'load_gold');

	BEGIN TRY

    SET @Start_load = GETDATE();
	PRINT('=================================');
	PRINT('Loading The Gold Layer');
	PRINT('=================================');

    
    SET @Missing_tickers =
    (
    SELECT STRING_AGG(ticker, ',') AS tickers_not_in_dim
    FROM(
	    SELECT DISTINCT(ticker)
	    FROM Silver.stocks_prices AS s
	    WHERE NOT EXISTS (SELECT 1 FROM Gold.dim_ticker WHERE ticker = s.ticker) AND s.loaded_at > @Last_run)
    AS unmatched_tickers
    )

    IF @Missing_tickers IS NOT NULL
        PRINT('Warning: Tickers in Silver Not Found in Dim_ticker: ' + @Missing_tickers);
    SELECT @Missing_tickers AS missing_tickers;

	MERGE Gold.fact_stock_prices AS target
    USING (
        SELECT
            dim.ticker_id,
            stock.date,
            stock.open_price,
            stock.high_price,
            stock.low_price,
            stock.close_price,
            stock.volume
        FROM Silver.stocks_prices AS stock
        INNER JOIN Gold.dim_ticker AS dim
        ON stock.ticker = dim.ticker
        WHERE stock.loaded_at > @Last_run
    ) AS source
    ON target.ticker_id = source.ticker_id AND target.date = source.date

    WHEN MATCHED THEN
        UPDATE SET
            target.open_price = source.open_price,
            target.high_price = source.high_price,
            target.low_price = source.low_price,
            target.close_price = source.close_price,
            target.volume = source.volume

    WHEN NOT MATCHED THEN
        INSERT (ticker_id, date, open_price, high_price, low_price, close_price, volume)
        VALUES (source.ticker_id, source.date, source.open_price, source.high_price, source.low_price, source.close_price, source.volume)
        OUTPUT $action INTO @Merge_results;

	SET @End_load = GETDATE();

    SELECT
        action_taken,
        COUNT(action_taken) AS row_count 
    FROM @Merge_results
    GROUP BY action_taken;

  
	PRINT('>> Load Duration: ' + CAST(DATEDIFF(second, @Start_load, @End_load) AS VARCHAR) + ' Seconds');
	PRINT('=================================');

    UPDATE Pipeline.load_log
    SET last_run = @End_load
    WHERE procedure_name = 'load_gold';

    END TRY 

    BEGIN CATCH

    PRINT('=================================');
    PRINT('Error Occured During Loading Gold Layer.');
    PRINT('Error Message: ' + ERROR_MESSAGE());
    PRINT('Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR));
    PRINT('Error State: ' + CAST(ERROR_STATE() AS VARCHAR));
    PRINT('=================================');
    THROW;

    END CATCH

END