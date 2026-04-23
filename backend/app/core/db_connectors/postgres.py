import psycopg2
from psycopg2 import sql


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


def test_postgres_connection(payload) -> dict:
    conn = None
    cur = None
    try:
        conn = _connect(payload)
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


def get_postgres_objects(payload):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()

        cur.execute(
            '''
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_type = 'BASE TABLE'
            ORDER BY table_name
            '''
        )
        tables = [row[0] for row in cur.fetchall()]

        cur.execute(
            '''
            SELECT table_name
            FROM information_schema.views
            WHERE table_schema = 'public'
            ORDER BY table_name
            '''
        )
        views = [row[0] for row in cur.fetchall()]

        cur.execute(
            '''
            SELECT routine_name
            FROM information_schema.routines
            WHERE specific_schema = 'public'
              AND routine_type = 'FUNCTION'
            ORDER BY routine_name
            '''
        )
        functions = [row[0] for row in cur.fetchall()]

        return [
            {
                "key": "tables",
                "label": "Tables",
                "items": [{"name": name, "subtitle": "table", "objectType": "table"} for name in tables],
            },
            {
                "key": "views",
                "label": "Views",
                "items": [{"name": name, "subtitle": "view", "objectType": "view"} for name in views],
            },
            {
                "key": "functions",
                "label": "Functions",
                "items": [{"name": name, "subtitle": "function", "objectType": "function"} for name in functions],
            },
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

        cur.execute(
            '''
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
            ''',
            (object_name,),
        )

        results = []
        for row in cur.fetchall():
            results.append(
                {
                    "name": row[0],
                    "dataType": row[1],
                    "isNullable": str(row[2]).upper() == "YES",
                    "flag": "PK" if row[3] else None,
                }
            )
        return results

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

        query = sql.SQL("SELECT * FROM {}.{} LIMIT %s").format(
            sql.Identifier("public"),
            sql.Identifier(object_name),
        )
        cur.execute(query, (limit,))

        columns = [desc[0] for desc in cur.description]
        rows = [list(row) for row in cur.fetchall()]
        return columns, rows

    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()
