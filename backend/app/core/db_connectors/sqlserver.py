import pyodbc

def test_sqlserver_connection(payload) -> dict:
    try:
        database = payload.database or "master"
        conn_str = (
            "DRIVER={ODBC Driver 17 for SQL Server};"
            f"SERVER={payload.host},{payload.port};"
            f"DATABASE={database};"
            f"UID={payload.username};"
            f"PWD={payload.password};"
            "TrustServerCertificate=yes;"
        )

        conn = pyodbc.connect(conn_str, timeout=10)
        cursor = conn.cursor()
        cursor.execute("SELECT @@VERSION")
        row = cursor.fetchone()
        conn.close()

        return {
            "success": True,
            "message": f"Connected OK. SQL Server version: {row[0]}",
            "provider": "sqlserver",
        }

    except Exception as e:
        return {
            "success": False,
            "message": str(e),
            "provider": "sqlserver",
        }
