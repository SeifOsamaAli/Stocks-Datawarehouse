/*
============================================
DDL Scripts: Create Bronze Tables
============================================

Script Purpose:
	This Script Creates Tables In The 'Bronze' Schema, Dropping The Table If It's Already Exists.
	Run This Script To Re-Define The DDL Strucutre Of The 'Bronze' Table.
*/

IF OBJECT_ID ('Bronze.stocks_prices', 'U') IS NOT NULL
	DROP TABLE Bronze.stocks_prices

CREATE TABLE Bronze.stocks_prices(
	ticker			VARCHAR(12),
	date			VARCHAR(12),
	open_price		VARCHAR(12),
	high_price		VARCHAR(12),
	low_price		VARCHAR(12),
	close_price		VARCHAR(12),
	volume			VARCHAR(12),
	PRIMARY KEY (ticker, date)
);