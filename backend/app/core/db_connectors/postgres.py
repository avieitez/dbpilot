import psycopg2


def test_postgres_connection(payload) -> dict:
    conn = None
    cur = None
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

        return {
            "success": True,
            "message": "PostgreSQL connection successful",
            "provider": "postgresql",
        }

    except Exception as e:
        return {
            "success": False,
            "message": str(e),
            "provider": "postgresql",
        }
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()
