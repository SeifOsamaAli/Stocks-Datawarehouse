IF OBJECT_ID ('Gold.fact_stock_prices', 'U') IS NOT NULL
	DROP TABLE Gold.fact_stock_prices

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
