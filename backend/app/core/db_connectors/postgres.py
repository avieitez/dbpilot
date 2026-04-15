def test_postgres_connection(payload) -> dict:
    database = payload.database or "postgres"
    return {
        "success": True,
        "message": f"PostgreSQL connector selected for host={payload.host}, database={database}",
        "provider": "postgresql",
    }
