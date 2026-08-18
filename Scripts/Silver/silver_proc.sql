/*
============================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
============================================

Script Purpose:
	This Stored Procedure Performs The ETL (Extract, Transform, Load) Process To
	Populate The 'Silver' Schema Tables From The 'Bronze' Schema.

	Actions Performed:
		- Truncates No Data (Reused History Is Preserved).
		- Casts Raw VARCHAR Columns From Bronze Into Their Proper Silver Data Types
		  (DECIMAL(11,4) For Prices, INT For Volume, DATE For Date), Using TRY_CAST
		  So A Single Bad/Uncastable Value Becomes NULL Instead Of Failing The
		  Entire Load.
		- Filters Bronze To Only Rows Where 'loaded_at' Is Newer Than This
		  Procedure's Last Successful Run (Read From Silver.load_log), Instead Of
		  Rescanning Bronze's Entire History On Every Run. This Keeps The Load Fast
		  As Bronze Grows, Since Only New Or Recently Corrected Rows Are Considered.
		- Uses MERGE To Insert New (Ticker, Date) Rows And Update Existing Ones,
		  Based On That Filtered Set.
		- Wrapped In TRY/CATCH: Any Failure Triggers A ROLLBACK And Prints
		  Diagnostic Error Information (Error Message, Line, Severity).
		- Reports Load Results (Row Counts Per Action: INSERT / UPDATE) And
		  Total Load Duration.
		- On A Successful Run Only, Updates Silver.load_log's 'last_run' Timestamp
		  For This Procedure, So The Next Run's Filter Advances Correctly. If The
		  Load Fails, 'last_run' Is Left Untouched, So Nothing Is Skipped Next Time.

Dependencies:
	Requires 'Bronze.stocks_prices' To Have A 'loaded_at' Column (Set On Every
	Insert/Update By bronze_connect.py), And Requires 'Silver.load_log' To Exist
	With A Seeded Row For procedure_name = 'load_silver'.

Parameters:
	None.
	This Stored Procedure Does Not Accept Any Parameters Or Return Any Values.

Usage Example:
	EXEC Silver.load_silver;
*/


CREATE OR ALTER PROCEDURE Silver.load_silver AS 
SET NOCOUNT ON;
BEGIN

    -- Creating Variables
	DECLARE @Start_load DATETIME, @End_load DATETIME
    DECLARE @Merge_results TABLE (action_taken VARCHAR(10)); 
    DECLARE @Last_run DATETIME2

    SET @Last_run = (SELECT last_run FROM Silver.load_log WHERE procedure_name = 'load_silver');

	BEGIN TRY

	SET @Start_load = GETDATE();
	PRINT('=================================');
	PRINT('Loading The Silver Layer');
	PRINT('=================================');

	MERGE Silver.stocks_prices AS target
    USING (
        SELECT
            TRIM(ticker) AS ticker,
            TRY_CAST(date AS date) AS date,
            TRY_CAST(open_price AS DECIMAL(11,4)) AS open_price,
            TRY_CAST(high_price AS DECIMAL(11,4)) AS high_price,
            TRY_CAST(low_price AS DECIMAL(11,4)) AS low_price,
            TRY_CAST(close_price AS DECIMAL(11,4)) AS close_price,
            TRY_CAST(volume AS INT) AS volume
        FROM Bronze.stocks_prices
        WHERE loaded_at > @Last_run
    ) AS source
    ON target.ticker = source.ticker AND target.date = source.date

    WHEN MATCHED THEN
        UPDATE SET
            target.open_price = source.open_price,
            target.high_price = source.high_price,
            target.low_price = source.low_price,
            target.close_price = source.close_price,
            target.volume = source.volume

    WHEN NOT MATCHED THEN
        INSERT (ticker, date, open_price, high_price, low_price, close_price, volume)
        VALUES (source.ticker, source.date, source.open_price, source.high_price, source.low_price, source.close_price, source.volume)
        OUTPUT $action INTO @Merge_results;

	SET @End_load = GETDATE();

    SELECT
        action_taken,
        COUNT(action_taken) AS row_count 
    FROM @Merge_results
    GROUP BY action_taken;

  
	PRINT('>> Load Duration: ' + CAST(DATEDIFF(second, @Start_load, @End_load) AS VARCHAR) + ' Seconds');
	PRINT('=================================');

    UPDATE Silver.load_log
    SET last_run = @End_load
    WHERE procedure_name = 'load_silver';

    END TRY 

    BEGIN CATCH

    PRINT('=================================');
    PRINT('Error Occured During Loading Silver Layer.');
    PRINT('Error Message: ' + ERROR_MESSAGE());
    PRINT('Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR));
    PRINT('Error State: ' + CAST(ERROR_STATE() AS VARCHAR));
    PRINT('=================================');
    THROW;

    END CATCH

END