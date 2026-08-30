/*
=====================================================
Create Database And Schemas
=====================================================

Script Purpose:
	Creating A New Database Called 'Stocks_Datawarehouse' After Checking If It Already Exists.
	If The Database Exists It's Dropped And Recreated. Additionally, The Script Sets Up 3 Schemas
	Withing The Database: 'Bronze', 'Silver' & 'Gold'.

Warning:
	Running The Script Will Drop The Entire 'Stocks_Datawarehouse' Database If It Exists.
	All Data Inside The Database Will Be Permanetly Deleted.
	Ensure You Have Proper Backup Before Running This Script.
*/

USE master;

-- Drop & Recreate The 'Stocks_Datawarehouse' Database.
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Stocks_Datawarehouse')
BEGIN
	ALTER DATABASE Stocks_Datawarehouse SET single_user WITH ROLLBACK IMMEDIATE;
	DROP DATABASE Stocks_Datawarehouse
END;
GO

-- Create Database
CREATE DATABASE Stocks_Datawarehouse
USE Stocks_Datawarehouse
GO

-- Create Schemas
CREATE SCHEMA Bronze;
GO

CREATE SCHEMA Silver;
GO

CREATE SCHEMA Gold;
GO

CREATE SCHEMA Pipeline;
GO