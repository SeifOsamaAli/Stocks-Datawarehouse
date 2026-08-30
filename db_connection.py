import pyodbc
import os
from dotenv import load_dotenv

load_dotenv()

def create_connection():
    """
        Making The Connection Between SQL Server And Python Script.
        Explaining Which Driver, Server & Database We Are Using. While Using Windows Authentication
        Using The TrustServerCertificate (Bypasses errors caused by local, self-signed SQL Server certificates.)
            Production environments should use properly chained certificates from a trusted CA to prevent Man-in-the-Middle (MitM) attacks.

        Returns:
            pyodbc.Connection: An open connection object to the Stocks_Datawarehouse database.

        Raises:
            pyodbc.Error: If the connection cannot be established (e.g. SQL Server service
                not running, driver not installed, or invalid server name).
"""

    DRIVER = os.environ["DRIVER"]
    SERVER = os.environ["SERVER"]
    DATABASE = os.environ["DATABASE"]
    trusted_connection = 'yes'
    encrypt = 'yes;trustServerCertificate=yes'
    return pyodbc.connect(f'DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection={trusted_connection};Encrypt={encrypt}')