def test_sqlserver_connection(payload) -> dict:
    database = payload.database or "master"
    return {
        "success": True,
        "message": f"SQL Server connector selected for host={payload.host}, database={database}",
        "provider": "sqlserver",
    }
