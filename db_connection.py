import pyodbc

def create_connection():
    DRIVER = 'ODBC Driver 18 for SQL Server'
    SERVER = r'localhost\SQLEXPRESS'
    DATABASE = 'Stocks_Datawarehouse'
    trusted_connection = 'yes'
    encrypt = 'yes;trustServerCertificate=yes'
    return pyodbc.connect(f'DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection={trusted_connection};Encrypt={encrypt}')

