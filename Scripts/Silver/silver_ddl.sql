/*
============================================
DDL Scripts: Create Silver Tables
============================================

Script Purpose:
	This Script Creates Tables In The 'Silver' Schema, Dropping The Table If It's Already Exists.
	Run This Script To Re-Define The DDL Strucutre Of The 'Silver' Table.

	Unlike Bronze (Where Every Column Is Stored As VARCHAR), Silver Columns Are Cast To Their
	Proper Types (DECIMAL(11,4) For Prices, INT For Volume, DATE For Date) So The Data Can Be
	Used Directly In Aggregations, Comparisons, And Date Logic Without Relying On Implicit
	Conversion At Query Time.

	Unlike Bronze.stocks_prices, It Is Safe For This Script To Drop And Recreate The Table On
	Every Rerun. Silver Holds No Data Of Its Own — Every Row Here Is Fully Derived From
	Bronze.stocks_prices, So If This Table Is Ever Wiped, Running EXEC Silver.load_silver
	Rebuilds It Completely From Bronze, With No Data Lost.

	When The Table Is Dropped And Recreated, This Script Also Resets Pipeline.load_log's
	'last_run' For procedure_name = 'load_silver' Back To Its Original Seed Value. This Is
	Required: Silver.load_silver Only Reads Rows From Bronze.stocks_prices Where loaded_at Is
	Newer Than This Stored Timestamp, So Without This Reset, A Freshly Emptied Silver Table
	Would Be Silently Skipped On The Next Run — Silver.load_silver Would See No Rows In Bronze
	Newer Than Its Last (Pre-Rebuild) Run And Correctly, But Unhelpfully, Conclude There Is
	Nothing New To Load. This Also Has A Downstream Effect On Gold: Since Silver's Own
	'loaded_at' Column Gets Refreshed On Every Row Reprocessed By This Reset, The Next
	EXEC Gold.load_gold Run Will See All Of Silver As Newly Changed And Reprocess It Too,
	Even Though Gold.fact_stock_prices Itself Was Never Touched.

Dependencies:
	Assumes 'Pipeline.load_log' Already Exists With A Seeded Row For procedure_name =
	'load_silver' — If This Script Runs Before That Table Is Created, The Log-Reset Step
	Will Fail. Run Pipeline.load_log's DDL First On A Fresh Database Setup.

Known Limitation:
	This Reset Only Handles A Full Table Rebuild (The Table Is Completely Empty Afterward).
	It Does Not Detect Or Correct For Partial Data Loss (E.g. A Few Rows Manually Deleted) —
	In That Case, Pipeline.load_log's 'last_run' Would Remain Ahead Of What The Table's Actual
	Contents Would Suggest, And Silver.load_silver Would Not Automatically Recover The Missing
	Rows.
*/

IF OBJECT_ID ('Silver.stocks_prices', 'U') IS NOT NULL
BEGIN
	DROP TABLE Silver.stocks_prices;
	UPDATE Pipeline.load_log SET last_run = '2000-01-01' WHERE procedure_name = 'load_silver';
END

CREATE TABLE Silver.stocks_prices(
	ticker			VARCHAR(12),
	date			date,
	open_price		DECIMAL(11, 4),
	high_price		DECIMAL(11, 4),
	low_price		DECIMAL(11, 4),
	close_price		DECIMAL(11, 4),
	volume			INT,
	loaded_at DATETIME2 DEFAULT GETDATE() NOT NULL,
	PRIMARY KEY (ticker, date)
);