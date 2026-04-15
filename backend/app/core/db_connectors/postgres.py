import psycopg2

def test_postgres_connection(payload) -> dict:
    try:
        conn = psycopg2.connect(
            host=payload.host,
            port=payload.port,
            dbname=payload.database,
            user=payload.username,
            password=payload.password,
            sslmode="require",
            connect_timeout=5,
        )

        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.fetchone()

        cur.close()
        conn.close()

        return {
            "success": True,
            "message": "Connected to PostgreSQL successfully",
            "provider": "postgresql",
        }

    except Exception as e:
        return {
            "success": False,
            "message": str(e),
            "provider": "postgresql",
        }