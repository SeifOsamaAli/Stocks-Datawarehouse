CREATE TABLE bronze_stocks_price(
	ticker			VARCHAR(12),
	date			VARCHAR(12),
	open_price		VARCHAR(12),
	high_price		VARCHAR(12),
	low_price		VARCHAR(12),
	close_price		VARCHAR(12),
	volume			VARCHAR(12),
	PRIMARY KEY (ticker, date)
);