/*
============================================
DDL Scripts: Create Silver Control Table (load_log)
============================================

Script Purpose:
	This Script Creates The 'Silver.load_log' Table Only If It Does Not Already
	Exist, And Seeds It With A Starting Row For 'load_silver' If That Row Is
	Missing. It Is Intentionally Non-Destructive — Unlike Silver.stocks_prices —
	Because This Table Is Not Derived Data. It Stores Pipeline State (When
	Silver.load_silver Last Ran Successfully), And Dropping It Would Erase That
	State, Silently Resetting The Incremental Filter Back To "Process
	Everything," Undoing The Whole Point Of Tracking It.

	Purpose Of The Table:
		Silver.load_silver Filters Bronze.stocks_prices Down To Only Rows
		Changed Since Its Last Successful Run (WHERE loaded_at > @Last_run),
		Instead Of Rescanning All Of Bronze Every Time. That Comparison Value
		Has To Be Read From Somewhere That Survives Between Separate
		Executions — A SQL Variable Only Lives For One Run And Then Vanishes.
		This Table Is That Persistent Storage.

	Why 'procedure_name' Exists:
		It Is A Plain Text Label, Not A Special SQL Concept — It Exists So
		This Table Can Track More Than One Procedure's Last-Run State In The
		Future (E.g. If Silver.check_data_quality Ever Needed The Same
		Tracking), Rather Than Being Permanently Limited To One Hardcoded
		Fact. PRIMARY KEY (procedure_name) Enforces Exactly One Row Per
		Tracked Procedure — This Is Deliberately A Single Overwritten Row,
		Not A Growing History Log, Since The Filter Only Ever Needs The Most
		Recent Value.

	Why The Seed INSERT Is A Separate Statement:
		It Runs Under Its Own IF NOT EXISTS Check, Independent Of The
		CREATE TABLE Block Above It. This Means It Self-Heals Every Time
		This Script Runs — Not Just The One Time The Table Is First Created —
		Covering The Edge Case Where The Table Exists But Its Seed Row Is
		Somehow Missing. The Seed Value ('2000-01-01') Is Deliberately Far
		Older Than Any Real loaded_at Timestamp, So The First Filtered Run In
		Silver.load_silver Doesn't Accidentally Exclude Real Data.
*/


IF OBJECT_ID ('Pipeline.load_log', 'U') IS NULL

BEGIN

	CREATE TABLE Pipeline.load_log(
		procedure_name VARCHAR(50),
		last_run DATETIME2 DEFAULT GETDATE(),
		PRIMARY KEY(procedure_name)
	);
END


IF NOT EXISTS (SELECT 1 FROM Pipeline.load_log WHERE procedure_name = 'load_silver')
INSERT INTO Pipeline.load_log (procedure_name, last_run) VALUES ('load_silver', '2000-01-01');

IF NOT EXISTS (SELECT 1 FROM Pipeline.load_log WHERE procedure_name = 'load_gold')
INSERT INTO Pipeline.load_log (procedure_name, last_run) VALUES ('load_gold', '2000-01-01');