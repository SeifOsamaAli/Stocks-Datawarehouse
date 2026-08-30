/*
============================================
DDL Scripts: Create Gold Stock Prices Fact Table
============================================

Script Purpose:
	This Script Creates The 'Gold.fact_stock_prices' Table, Dropping It First
	If It Already Exists. Unlike 'Gold.dim_ticker', This Table Is Safe To
	Treat As Destructive/Disposable — Every Row Here Is Fully Recomputable
	From 'Silver.stocks_prices' By Running EXEC Gold.load_gold, So Rebuilding
	It Costs Nothing Beyond Re-Running That Procedure.

	When The Table Is Dropped And Recreated, This Script Also Resets
	Pipeline.load_log's 'last_run' For procedure_name = 'load_gold' Back To
	Its Original Seed Value. This Is Required: Gold.load_gold Only Reads
	Rows From Silver.stocks_prices Where loaded_at Is Newer Than This Stored
	Timestamp, So Without This Reset, A Freshly Emptied Fact Table Would Be
	Silently Skipped On The Next Run — Gold.load_gold Would See No Rows In
	Silver Newer Than Its Last (Pre-Rebuild) Run And Correctly, But
	Unhelpfully, Conclude There Is Nothing New To Load.

	Grain: One Row Per (ticker_id, date), Matching Silver's Own
	(ticker, date) Grain — The Ticker Is Represented Here By Its Surrogate
	Key (ticker_id) Rather Than Its Text Symbol, Referencing
	Gold.dim_ticker(ticker_id) Via A FOREIGN KEY Constraint. This Means An
	Insert Here Will Be Rejected If The Corresponding Ticker Does Not Yet
	Exist In Gold.dim_ticker — See Gold.load_gold, Which Uses An INNER JOIN
	To Silently Exclude (And Separately Warn About) Any Such Rows Rather Than
	Attempting An Insert That Would Fail This Constraint.

	No Derived/Computed Columns (E.g. Day-Over-Day % Change, Moving Averages)
	Are Stored Here Deliberately — These Are Always Computed At Query Time
	From The Raw Price Columns, Since A Stored Derived Value Could Silently
	Go Stale If The Underlying Price It Was Computed From Is Later Corrected.

Dependencies:
	Assumes 'Pipeline.load_log' Already Exists With A Seeded Row For
	procedure_name = 'load_gold' — If This Script Runs Before That Table Is
	Created, The Log-Reset Step Will Fail. Run Pipeline.load_log's DDL First
	On A Fresh Database Setup.

Known Limitation:
	This Reset Only Handles A Full Table Rebuild (The Table Is Completely
	Empty Afterward). It Does Not Detect Or Correct For Partial Data Loss
	(E.g. A Few Rows Manually Deleted) — In That Case, Pipeline.load_log's
	'last_run' Would Remain Ahead Of What The Table's Actual Contents Would
	Suggest, And Gold.load_gold Would Not Automatically Recover The Missing
	Rows.
*/

IF OBJECT_ID ('Gold.fact_stock_prices', 'U') IS NOT NULL
BEGIN
	DROP TABLE Gold.fact_stock_prices;
	UPDATE Pipeline.load_log SET last_run = '2000-01-01' WHERE procedure_name = 'load_gold';
END

CREATE TABLE Gold.fact_stock_prices(
	ticker_id		INT NOT NULL,
	date			DATE NOT NULL,
	open_price		DECIMAL(11, 4),
	high_price		DECIMAL(11, 4),
	low_price		DECIMAL(11, 4),
	close_price		DECIMAL(11, 4),
	volume			INT,
	PRIMARY KEY (ticker_id, date),
	CONSTRAINT FK_ticker_id
	FOREIGN KEY (ticker_id) REFERENCES Gold.dim_ticker (ticker_id)
);
