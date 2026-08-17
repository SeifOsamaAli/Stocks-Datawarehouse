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
*/

IF OBJECT_ID ('Silver.stocks_prices', 'U') IS NOT NULL
	DROP TABLE Silver.stocks_prices

CREATE TABLE Silver.stocks_prices(
	ticker			VARCHAR(12),
	date			date,
	open_price		DECIMAL(11, 4),
	high_price		DECIMAL(11, 4),
	low_price		DECIMAL(11, 4),
	close_price		DECIMAL(11, 4),
	volume			INT,
	PRIMARY KEY (ticker, date)
);