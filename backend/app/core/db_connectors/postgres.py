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


def build_postgres_default_query(object_name: str, object_type: str, schema_name: str | None = None) -> str:
    qualified = f'"{_schema(schema_name)}"."{object_name}"'
    clean_type = (object_type or "").lower()
    if clean_type == "function":
        return f"SELECT *\nFROM {qualified}();"
    if clean_type == "extension":
        return f"-- Extension {object_name}. No preview query available."
    return f"SELECT *\nFROM {qualified};"


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
            SELECT schemaname, matviewname
            FROM pg_matviews
            WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
            ORDER BY schemaname, matviewname
        """)
        materialized_views = cur.fetchall()

        cur.execute("""
            SELECT routine_schema, routine_name
            FROM information_schema.routines
            WHERE routine_schema NOT IN ('pg_catalog', 'information_schema')
              AND routine_type = 'FUNCTION'
            ORDER BY routine_schema, routine_name
        """)
        functions = cur.fetchall()

        cur.execute("""
            SELECT COALESCE(n.nspname, ''), e.extname
            FROM pg_extension e
            LEFT JOIN pg_namespace n ON n.oid = e.extnamespace
            ORDER BY e.extname
        """)
        extensions = cur.fetchall()

        def item(row, object_type):
            schema, name = row[0], row[1]
            subtitle = f"{schema} · {object_type}" if schema else object_type
            return {
                "name": name,
                "schemaName": schema or None,
                "subtitle": subtitle,
                "objectType": object_type,
                "defaultQuery": build_postgres_default_query(name, object_type, schema or None),
            }

        return [
            {"key": "tables", "label": "Tables", "items": [item(row, "table") for row in tables]},
            {"key": "views", "label": "Views", "items": [item(row, "view") for row in views]},
            {"key": "functions", "label": "Functions", "items": [item(row, "function") for row in functions]},
            {"key": "materializedViews", "label": "Materialized Views", "items": [item(row, "materialized_view") for row in materialized_views]},
            {"key": "extensions", "label": "Extensions", "items": [item(row, "extension") for row in extensions]},
        ]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()

def get_postgres_object_structure(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() not in {"table", "view", "materialized_view"}:
        return []
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("""
            SELECT a.attname AS column_name,
                   CASE
                       WHEN format_type(a.atttypid, a.atttypmod) IS NOT NULL THEN format_type(a.atttypid, a.atttypmod)
                       ELSE t.typname
                   END AS data_type,
                   a.attnotnull,
                   CASE WHEN pk.attname IS NOT NULL THEN 1 ELSE 0 END AS is_primary_key
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_type t ON t.oid = a.atttypid
            LEFT JOIN (
                SELECT kcu.table_schema, kcu.table_name, kcu.column_name AS attname
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON tc.constraint_name = kcu.constraint_name
                 AND tc.table_schema = kcu.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY'
            ) pk
              ON pk.table_schema = n.nspname
             AND pk.table_name = c.relname
             AND pk.attname = a.attname
            WHERE n.nspname = %s
              AND c.relname = %s
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY a.attnum
        """, (_schema(schema_name), object_name))
        return [
            {
                "name": row[0],
                "dataType": row[1],
                "isNullable": not bool(row[2]),
                "flag": "PK" if row[3] else None,
            }
            for row in cur.fetchall()
        ]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()

def get_postgres_object_preview(payload, object_name: str, object_type: str, limit: int, schema_name: str | None = None):
    if (object_type or "").lower() not in {"table", "view", "materialized_view"}:
        return [], []
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        query = pg_sql.SQL("SELECT * FROM {}.{} LIMIT %s").format(pg_sql.Identifier(_schema(schema_name)), pg_sql.Identifier(object_name))
        cur.execute(query, (limit,))
        columns = [desc[0] for desc in cur.description]
        rows = [[_serialize_value(value) for value in row] for row in cur.fetchall()]
        return columns, rows
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_object_definition(payload, object_name: str, object_type: str, schema_name: str | None = None):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        schema = _schema(schema_name)
        clean_type = (object_type or "").lower()
        if clean_type == "view":
            cur.execute("SELECT pg_get_viewdef(%s::regclass, true)", (f'{schema}.{object_name}',))
            row = cur.fetchone()
            return row[0] if row else None
        if clean_type == "function":
            cur.execute("""
                SELECT pg_get_functiondef(p.oid)
                FROM pg_proc p
                JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = %s AND p.proname = %s
                ORDER BY p.oid LIMIT 1
            """, (schema, object_name))
            row = cur.fetchone()
            return row[0] if row else None
        return None
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def get_postgres_object_parameters(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() != "function":
        return []
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("""
            SELECT parameter_name, data_type, parameter_mode
            FROM information_schema.parameters
            WHERE specific_schema = %s AND specific_name LIKE %s AND parameter_name IS NOT NULL
            ORDER BY ordinal_position
        """, (_schema(schema_name), f"{object_name}%"))
        return [{"name": row[0], "dataType": row[1], "direction": row[2], "hasDefault": None} for row in cur.fetchall()]
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def execute_postgres_query(payload, sql: str, limit: int, timeout_seconds: int = 30):
    conn = None
    cur = None
    try:
        conn = _connect(payload)
        cur = conn.cursor()
        cur.execute("SET statement_timeout = %s", (int(timeout_seconds) * 1000,))
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
