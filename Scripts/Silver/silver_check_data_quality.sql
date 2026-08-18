/*
============================================
Stored Procedure: Check Silver Data Quality
============================================

Script Purpose:
	This Stored Procedure Runs Data Quality Checks Against The 'Silver.stocks_prices'
	Table And Reports Any Issues Found. It Is A Read-Only Reporting Procedure —
	It Does Not Modify, Fix, Or Remove Any Data.

	Checks Performed:
		- Hard Error: Price Inversion (high_price < low_price).
		- Hard Error: Negative Value (Any Of high_price, low_price, close_price,
		  open_price, Volume Is Negative).
		- Soft Flag: Zero Value (Any Of high_price, low_price, close_price,
		  open_price, Volume Is Exactly Zero — Valid But Worth Reviewing).

	For Each Check, Returns Both A Row Count And The Full Offending Rows, So The
	Reader Can Immediately See The Scale Of An Issue And Investigate It Directly.

	This Procedure Is Intended To Be Run Manually After Silver.load_silver, As A
	Report To Review — It Does Not Block Or Gate The Load Itself. Data Quality
	Checking Is Deliberately Kept Separate From The Load Rather Than Built Into
	The MERGE (See README For Full Reasoning).

	This Procedure Only Reports Issues — It Never Attempts To Fix Them (E.g. It
	Does Not Sign-Flip Negative Values Or Swap An Inverted High/Low). Bad Data
	Cannot Be Safely Auto-Corrected Without Risking A Confidently Wrong Guess
	(See README For Full Reasoning).

Design Note (Temp Tables Vs. CTEs):
	The Negative Value And Zero Value Checks Each Need Their Filtered Row Set Twice
	(Once For COUNT(*), Once For The Detail SELECT). A CTE Is Scoped To Only The
	Single Statement Immediately Following It, So It Cannot Be Reused Across Two
	Separate Statements. A Temp Table Persists For The Duration Of The Session/Batch,
	So It Is Used Here Instead — The Filter Logic Is Written Once Into
	#negative_rows / #zero_rows, Then Queried Twice.

Parameters:
	None.
	This Stored Procedure Does Not Accept Any Parameters Or Return Any Values.

Usage Example:
	EXEC Silver.check_data_quality;
*/

CREATE OR ALTER PROCEDURE Silver.check_data_quality AS
SET NOCOUNT ON;
BEGIN

	PRINT('===============================');
	PRINT('Hard Error: Price Inversion');
	SELECT COUNT(*) AS Count_Wrong_Price
	FROM Silver.stocks_prices
	WHERE high_price < low_price;

	SELECT
		ticker,
		date,
		high_price,
		low_price
	FROM Silver.stocks_prices
	WHERE high_price < low_price;
	PRINT('===============================');


	IF OBJECT_ID('tempdb..#negative_rows') IS NOT NULL
		DROP TABLE #negative_rows;

	SELECT
		ticker,
		date,
		high_price,
		low_price,
		close_price,
		open_price,
		volume
	INTO #negative_rows
	FROM Silver.stocks_prices
	WHERE	high_price < 0 OR
			low_price < 0 OR
			close_price < 0 OR
			open_price < 0 OR
			volume < 0;

	PRINT('===============================');
	PRINT('Hard Error: Negative Value');
	SELECT COUNT(*) AS Count_Negative_Rows
	FROM #negative_rows;

	SELECT *
	FROM #negative_rows;
	PRINT('===============================');


	IF OBJECT_ID('tempdb..#zero_rows') IS NOT NULL
		DROP TABLE #zero_rows;

	SELECT
		ticker,
		date,
		high_price,
		low_price,
		close_price,
		open_price,
		volume
	INTO #zero_rows
	FROM Silver.stocks_prices
	WHERE	high_price = 0 OR
			low_price = 0 OR
			close_price = 0 OR
			open_price = 0 OR
			volume = 0;

	PRINT('===============================');
	PRINT('Soft Flag: Zero Value');
	SELECT COUNT(*) AS Count_Zero_Rows
	FROM #zero_rows;

	SELECT *
	FROM #zero_rows;
	PRINT('===============================');

END