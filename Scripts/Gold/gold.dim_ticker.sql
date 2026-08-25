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