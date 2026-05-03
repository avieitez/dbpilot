import psycopg2
from psycopg2 import sql as pg_sql


def _connect(payload):
    return psycopg2.connect(
        host=payload.host,
        port=payload.port,
        dbname=payload.database,
        user=payload.username,
        password=payload.password,
        sslmode="require",
        connect_timeout=5,
    )


def _serialize_value(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def execute_postgres_query(payload, sql: str, limit: int):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()

        cur.execute(sql)

        # INSERT / UPDATE / DELETE
        if cur.description is None:
            conn.commit()
            affected = cur.rowcount if cur.rowcount is not None else 0
            return ["message"], [[f"Query OK. Rows affected: {affected}"]]

        # SELECT
        columns = [desc[0] for desc in cur.description]
        rows = []
        for index, row in enumerate(cur.fetchall()):
            if index >= limit:
                break
            rows.append([_serialize_value(value) for value in row])

        return columns, rows

    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()
