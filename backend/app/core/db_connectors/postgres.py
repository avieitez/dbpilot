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


def _schema(schema_name: str | None) -> str:
    return (schema_name or "public").strip() or "public"


def _qualified_text(object_name: str, schema_name: str | None = None) -> str:
    return f'"{_schema(schema_name)}"."{object_name}"'


def build_postgres_default_query(object_name: str, object_type: str, schema_name: str | None = None) -> str:
    qualified = _qualified_text(object_name, schema_name)
    if (object_type or "").lower() == "function":
        return f"SELECT *\nFROM {qualified}();"
    return f"SELECT *\nFROM {qualified}\nLIMIT 100;"


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
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
              AND table_type = 'BASE TABLE'
            ORDER BY table_schema, table_name
        """)
        tables = cur.fetchall()

        cur.execute("""
            SELECT table_schema, table_name
            FROM information_schema.views
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
            ORDER BY table_schema, table_name
        """)
        views = cur.fetchall()

        cur.execute("""
            SELECT routine_schema, routine_name
            FROM information_schema.routines
            WHERE specific_schema NOT IN ('pg_catalog', 'information_schema')
              AND routine_type = 'FUNCTION'
            ORDER BY routine_schema, routine_name
        """)
        functions = cur.fetchall()

        def item(row, object_type):
            schema, name = row[0], row[1]
            return {
                "name": name,
                "schemaName": schema,
                "subtitle": f"{schema} · {object_type}",
                "objectType": object_type,
                "defaultQuery": build_postgres_default_query(name, object_type, schema),
            }

        return [
            {"key": "tables", "label": "Tables", "items": [item(row, "table") for row in tables]},
            {"key": "views", "label": "Views", "items": [item(row, "view") for row in views]},
            {"key": "functions", "label": "Functions", "items": [item(row, "function") for row in functions]},
        ]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_object_structure(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() == "function":
        return []

    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("""
            SELECT
                c.column_name,
                CASE
                    WHEN c.character_maximum_length IS NOT NULL
                        THEN c.data_type || '(' || c.character_maximum_length || ')'
                    WHEN c.numeric_precision IS NOT NULL AND c.numeric_scale IS NOT NULL
                        THEN c.data_type || '(' || c.numeric_precision || ',' || c.numeric_scale || ')'
                    ELSE c.data_type
                END AS data_type,
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
                AND tc.constraint_type = 'PRIMARY KEY'
            WHERE c.table_schema = %s
              AND c.table_name = %s
            ORDER BY c.ordinal_position
        """, (_schema(schema_name), object_name))

        return [
            {"name": row[0], "dataType": row[1], "isNullable": str(row[2]).upper() == "YES", "flag": "PK" if row[3] else None}
            for row in cur.fetchall()
        ]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_object_preview(payload, object_name: str, object_type: str, limit: int, schema_name: str | None = None):
    if (object_type or "").lower() == "function":
        return [], []

    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        query = pg_sql.SQL("SELECT * FROM {}.{} LIMIT %s").format(
            pg_sql.Identifier(_schema(schema_name)),
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
            affected = cur.rowcount if cur.rowcount is not None and cur.rowcount >= 0 else 0
            conn.commit()
            return ["message"], [[f"Query executed successfully. Rows affected: {affected}"]]
        columns = [desc[0] for desc in cur.description]
        rows = []
        for index, row in enumerate(cur.fetchall()):
            if index >= limit:
                break
            rows.append([_serialize_value(value) for value in row])
        return columns, rows
    except Exception:
        if conn is not None:
            conn.rollback()
        raise
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()
