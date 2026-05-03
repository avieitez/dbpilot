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


def test_postgres_connection(payload) -> dict:
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.fetchone()
        return {"success": True, "message": "PostgreSQL connection successful", "provider": "postgresql"}
    except Exception as e:
        return {"success": False, "message": str(e), "provider": "postgresql"}
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_objects(payload):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_type = 'BASE TABLE'
            ORDER BY table_name
        """)
        tables = [row[0] for row in cur.fetchall()]

        cur.execute("""
            SELECT table_name
            FROM information_schema.views
            WHERE table_schema = 'public'
            ORDER BY table_name
        """)
        views = [row[0] for row in cur.fetchall()]

        cur.execute("""
            SELECT routine_name
            FROM information_schema.routines
            WHERE specific_schema = 'public'
              AND routine_type = 'FUNCTION'
            ORDER BY routine_name
        """)
        functions = [row[0] for row in cur.fetchall()]

        return [
            {"key": "tables", "label": "Tables", "items": [{"name": n, "subtitle": "table", "objectType": "table"} for n in tables]},
            {"key": "views", "label": "Views", "items": [{"name": n, "subtitle": "view", "objectType": "view"} for n in views]},
            {"key": "functions", "label": "Functions", "items": [{"name": n, "subtitle": "function", "objectType": "function"} for n in functions]},
        ]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_object_structure(payload, object_name: str, object_type: str):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("""
            SELECT
                c.column_name,
                c.data_type,
                c.is_nullable,
                CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN 1 ELSE 0 END AS is_primary_key
            FROM information_schema.columns c
            LEFT JOIN information_schema.key_column_usage kcu
                ON c.table_name = kcu.table_name
                AND c.column_name = kcu.column_name
                AND c.table_schema = kcu.table_schema
            LEFT JOIN information_schema.table_constraints tc
                ON kcu.constraint_name = tc.constraint_name
                AND kcu.table_schema = tc.table_schema
            WHERE c.table_schema = 'public'
              AND c.table_name = %s
            ORDER BY c.ordinal_position
        """, (object_name,))

        return [
            {
                "name": row[0],
                "dataType": row[1],
                "isNullable": str(row[2]).upper() == "YES",
                "flag": "PK" if row[3] else None,
            }
            for row in cur.fetchall()
        ]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_object_preview(payload, object_name: str, object_type: str, limit: int):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        query = pg_sql.SQL("SELECT * FROM {}.{} LIMIT %s").format(
            pg_sql.Identifier("public"),
            pg_sql.Identifier(object_name),
        )
        cur.execute(query, (limit,))
        columns = [desc[0] for desc in cur.description]
        rows = [[_serialize_value(value) for value in row] for row in cur.fetchall()]
        return columns, rows
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def execute_postgres_query(payload, sql: str, limit: int):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute(sql)
        if cur.description is None:
            conn.commit()
            affected = cur.rowcount if cur.rowcount is not None else 0
            return ["message"], [[f"Query OK. Rows affected: {affected}"]]
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
