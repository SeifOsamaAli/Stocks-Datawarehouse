/*
============================================
DDL Scripts: Create Gold Ticker Dimension Table
============================================

Script Purpose:
	This Script Creates The 'Gold.dim_ticker' Table Only If It Does Not
	Already Exist. It Is Intentionally Non-Destructive — Unlike A Typical
	Drop-And-Recreate DDL Script — Because This Table Holds Company Metadata
	(Name, Sector, Industry, Exchange, Currency, Country) Sourced From Alpha
	Vantage's OVERVIEW Endpoint, One API Call Per Ticker. Losing This Table
	Means Genuinely Re-Fetching Every Ticker's Data From The API, Not A Free
	Recompute From Data Already In This Database. If This Table Already
	Exists, Running This Script Has No Effect.

	If You Need To Change The Table's Structure (E.g. Widen A Column, Add A
	New One), Do Not Rely On Rerunning This Script — It Will Silently Do
	Nothing. Use A Deliberate, Separate ALTER TABLE Statement Instead.

	ticker_id Is A Surrogate Key (IDENTITY), Not The Ticker Symbol Itself,
	So That Every Fact Row Referencing It Stays Stable Even If A Ticker's
	Symbol Is Ever Renamed — Only This One Row Would Need Updating, Not Every
	Historical Fact Row. 'ticker' Still Carries A UNIQUE Constraint (Not
	PRIMARY KEY) So Lookups By The Human-Readable Symbol Remain Fast And
	Guaranteed Unique.

Known Limitation:
	A Ticker Rename Is Not Detected Or Handled Automatically. A Renamed
	Ticker Will Appear As An Unmatched Ticker In Gold.load_gold's Warning
	Output Until Someone Manually Updates This Table's 'ticker' Column For
	The Existing Row (Preserving Its ticker_id), Rather Than Letting A New
	Row Get Created For What Is Actually The Same Company.
*/

IF OBJECT_ID ('Gold.dim_ticker', 'U') IS NULL

BEGIN

	CREATE TABLE Gold.dim_ticker(
		ticker_id		INT IDENTITY(1,1) PRIMARY KEY,
		ticker			VARCHAR(12) UNIQUE NOT NULL,
		company_name	VARCHAR(100) NOT NULL,
		sector			VARCHAR(100),
		industry		VARCHAR(100),
		exchange		VARCHAR(10),
		currency		VARCHAR(3),
		country			VARCHAR(50)
	);

END