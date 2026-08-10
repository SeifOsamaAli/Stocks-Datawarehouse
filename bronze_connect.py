from db_connection import create_connection
import os
import json

bronze_connection = create_connection()

cursor = bronze_connection.cursor()

folder_name = r"G:\Seko\Seif\Data Engineering\Stocks Project\Dataset"
files = os.listdir(folder_name)

json_files = [file for file in files if file.endswith(".json")]


for file in json_files:
    
    file_path = os.path.join(folder_name, file)
    with open(file_path, "r") as f:
        data = json.load(f)

    for ticker, dates_dict in data.items():
        for date, elements in dates_dict.items():

            open_price = elements["1. open"]
            high_price = elements["2. high"]
            low_price = elements["3. low"]
            close_price = elements["4. close"]
            volume = elements["5. volume"]

            cursor.execute("SELECT ticker, date FROM Bronze.stocks_prices WHERE ticker = ? AND date = ?", (ticker, date))
            exisiting_row = cursor.fetchone()

            if exisiting_row == None:
                cursor.execute("INSERT INTO Bronze.stocks_prices (ticker, date, open_price, high_price, low_price, close_price, volume) VALUES (?, ?, ?, ?, ?, ?, ?)", (ticker, date, open_price, high_price, low_price, close_price, volume))

            else:
                cursor.execute("UPDATE Bronze.stocks_prices SET open_price = ?, high_price = ?, low_price = ?, close_price = ?, volume =? WHERE ticker = ? AND date = ?", (open_price, high_price, low_price, close_price, volume, ticker, date))

bronze_connection.commit()
bronze_connection.close()