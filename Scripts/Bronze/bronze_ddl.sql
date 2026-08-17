/*
============================================
DDL Scripts: Create Bronze Tables
============================================

Script Purpose:
	This Script Creates The 'Bronze.stocks_prices' Table Only If It Does Not
	Already Exist. It Is Intentionally Non-Destructive — Unlike A Typical
	Drop-And-Recreate DDL Script — Because Bronze Holds The Pipeline's Only
	Copy Of Historical Data That Cannot Be Fully Re-Pulled From The Source API
	(Alpha Vantage Only Returns Recent History On Each Call). If This Table
	Already Exists, Running This Script Has No Effect.

	If You Need To Change The Table's Structure (E.g. Widen A Column, Add A
	New One), Do Not Rely On Rerunning This Script — It Will Silently Do
	Nothing. Use A Deliberate, Separate ALTER TABLE Statement Instead. This
	Includes The Case Where An Older Version Of This Table (E.g. One Created
	Before The 'loaded_at' Column Existed) Is Already Present — This Script
	Will Detect The Table As Existing And Skip Silently, Leaving It Missing
	'loaded_at' Rather Than Adding It.

	All Business Columns (Ticker, Date, Prices, Volume) Are Stored As VARCHAR,
	Untouched And Untyped — Casting Is A Deliberate Silver-Layer Decision, Not
	Something Done Silently During Ingestion.

	The Exception Is 'loaded_at' (DATETIME2, DEFAULT GETDATE(), NOT NULL) — This
	Is Pipeline Metadata, Not Trading Data. It Records When Each Row Was Last
	Written (Inserted Or Updated) By bronze_connect.py, So Downstream Layers
	(Silver) Can Filter For Recently Changed Rows Instead Of Rescanning The
	Entire Table On Every Run.
*/

IF OBJECT_ID ('Bronze.stocks_prices', 'U') IS NULL
	
BEGIN
	CREATE TABLE Bronze.stocks_prices(
		ticker			VARCHAR(12),
		date			VARCHAR(12),
		open_price		VARCHAR(12),
		high_price		VARCHAR(12),
		low_price		VARCHAR(12),
		close_price		VARCHAR(12),
		volume			VARCHAR(12),
		loaded_at		DATETIME2 DEFAULT GETDATE() NOT NULL,
		PRIMARY KEY (ticker, date)
	);
END