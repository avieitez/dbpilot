import pymssql



def _normalize_timeout_seconds(timeout_seconds: int | None) -> int:
    try:
        value = int(timeout_seconds or 30)
    except (TypeError, ValueError):
        value = 30
    return max(1, min(value, 600))

def _connect(payload, timeout_seconds: int = 30):
    timeout_seconds = _normalize_timeout_seconds(timeout_seconds)
    database = payload.database or "master"
    return pymssql.connect(
        server=payload.host,
        port=int(payload.port),
        user=payload.username,
        password=payload.password,
        database=database,
        login_timeout=10,
        timeout=int(timeout_seconds),
        charset="UTF-8",
    )


def _serialize_value(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def _clean_identifier(value: str) -> str:
    return (value or "").replace("[", "").replace("]", "").strip()


def _qualified_name(object_name: str, schema_name: str | None = None) -> str:
    schema = _clean_identifier(schema_name or "dbo")
    name = _clean_identifier(object_name)
    return f"[{schema}].[{name}]"


def build_sqlserver_default_query(object_name: str, object_type: str, schema_name: str | None = None) -> str:
    qualified = _qualified_name(object_name, schema_name)
    if (object_type or "").lower() == "procedure":
        return f"EXEC {qualified};"
    return f"SELECT *\nFROM {qualified};"


def test_sqlserver_connection(payload) -> dict:
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("SELECT @@VERSION")
        row = cursor.fetchone()
        return {"success": True, "message": f"Connected OK. SQL Server version: {row[0]}", "provider": "sqlserver"}
    except Exception as e:
        return {"success": False, "message": str(e), "provider": "sqlserver"}
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_objects(payload):
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT TABLE_SCHEMA, TABLE_NAME
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_TYPE = 'BASE TABLE'
              AND TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
            ORDER BY TABLE_SCHEMA, TABLE_NAME
        """)
        tables = cursor.fetchall()
        cursor.execute("""
            SELECT TABLE_SCHEMA, TABLE_NAME
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
            ORDER BY TABLE_SCHEMA, TABLE_NAME
        """)
        views = cursor.fetchall()
        cursor.execute("""
            SELECT ROUTINE_SCHEMA, ROUTINE_NAME
            FROM INFORMATION_SCHEMA.ROUTINES
            WHERE ROUTINE_TYPE = 'PROCEDURE'
              AND ROUTINE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA')
            ORDER BY ROUTINE_SCHEMA, ROUTINE_NAME
        """)
        procedures = cursor.fetchall()

        def item(row, object_type):
            schema, name = row[0], row[1]
            return {"name": name, "schemaName": schema, "subtitle": f"{schema} · {object_type}", "objectType": object_type, "defaultQuery": build_sqlserver_default_query(name, object_type, schema)}

        return [
            {"key": "tables", "label": "Tables", "items": [item(row, "table") for row in tables]},
            {"key": "views", "label": "Views", "items": [item(row, "view") for row in views]},
            {"key": "procedures", "label": "Procedures", "items": [item(row, "procedure") for row in procedures]},
        ]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_object_structure(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() == "procedure":
        return []
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT c.COLUMN_NAME,
                   CASE
                     WHEN c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL AND c.CHARACTER_MAXIMUM_LENGTH > 0 THEN CONCAT(c.DATA_TYPE, '(', c.CHARACTER_MAXIMUM_LENGTH, ')')
                     WHEN c.NUMERIC_PRECISION IS NOT NULL AND c.NUMERIC_SCALE IS NOT NULL THEN CONCAT(c.DATA_TYPE, '(', c.NUMERIC_PRECISION, ',', c.NUMERIC_SCALE, ')')
                     ELSE c.DATA_TYPE
                   END AS DATA_TYPE,
                   c.IS_NULLABLE,
                   CASE WHEN tc.CONSTRAINT_TYPE = 'PRIMARY KEY' THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
            FROM INFORMATION_SCHEMA.COLUMNS c
            LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
              ON c.TABLE_SCHEMA = kcu.TABLE_SCHEMA AND c.TABLE_NAME = kcu.TABLE_NAME AND c.COLUMN_NAME = kcu.COLUMN_NAME
            LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
              ON kcu.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA AND kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
            WHERE c.TABLE_NAME = %s AND (%s IS NULL OR c.TABLE_SCHEMA = %s)
            ORDER BY c.ORDINAL_POSITION
        """, (object_name, schema_name, schema_name))
        return [{"name": row[0], "dataType": row[1], "isNullable": str(row[2]).upper() == "YES", "flag": "PK" if row[3] else None} for row in cursor.fetchall()]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_object_preview(payload, object_name: str, object_type: str, limit: int, schema_name: str | None = None):
    if (object_type or "").lower() == "procedure":
        return [], []
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute(f"SELECT TOP {int(limit)} * FROM {_qualified_name(object_name, schema_name)}")
        columns = [column[0] for column in cursor.description]
        rows = [[_serialize_value(value) for value in row] for row in cursor.fetchall()]
        return columns, rows
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_object_definition(payload, object_name: str, object_type: str, schema_name: str | None = None):
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        qualified_for_object_id = f"{_clean_identifier(schema_name or 'dbo')}.{_clean_identifier(object_name)}"
        cursor.execute("SELECT OBJECT_DEFINITION(OBJECT_ID(%s))", (qualified_for_object_id,))
        row = cursor.fetchone()
        return row[0] if row and row[0] else None
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_object_parameters(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() != "procedure":
        return []
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT p.name, TYPE_NAME(p.user_type_id) AS type_name,
                   CASE WHEN p.is_output = 1 THEN 'OUT' ELSE 'IN' END AS direction,
                   p.has_default_value
            FROM sys.parameters p
            INNER JOIN sys.objects o ON p.object_id = o.object_id
            INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
            WHERE o.name = %s AND (%s IS NULL OR s.name = %s)
            ORDER BY p.parameter_id
        """, (object_name, schema_name, schema_name))
        return [{"name": row[0], "dataType": row[1], "direction": row[2], "hasDefault": bool(row[3])} for row in cursor.fetchall()]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def execute_sqlserver_query(payload, sql: str, limit: int, timeout_seconds: int = 30):
    conn = None
    cursor = None
    timeout_seconds = _normalize_timeout_seconds(timeout_seconds)
    try:
        conn = _connect(payload, timeout_seconds)
        cursor = conn.cursor()
        cursor.execute(sql)
        if cursor.description is None:
            affected = cursor.rowcount if cursor.rowcount is not None and cursor.rowcount >= 0 else 0
            conn.commit()
            return ["message"], [[f"Query executed successfully. Rows affected: {affected}"]]
        columns = [column[0] for column in cursor.description]
        rows = []
        for index, row in enumerate(cursor.fetchall()):
            if index >= limit:
                break
            rows.append([_serialize_value(value) for value in row])
        return columns, rows
    except Exception as exc:
        if conn is not None:
            conn.rollback()
        message = str(exc).lower()
        if "timeout" in message or "timed out" in message or "query cancelled" in message:
            raise TimeoutError(f"Query timed out after {timeout_seconds} seconds.") from exc
        raise
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()
