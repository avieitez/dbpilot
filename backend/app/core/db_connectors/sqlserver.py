import pymssql


def _connect(payload):
    database = payload.database or "master"
    return pymssql.connect(
        server=payload.host,
        port=int(payload.port),
        user=payload.username,
        password=payload.password,
        database=database,
        login_timeout=10,
        timeout=30,
        charset="UTF-8",
    )


def _serialize_value(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def test_sqlserver_connection(payload) -> dict:
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("SELECT @@VERSION")
        row = cursor.fetchone()
        return {
            "success": True,
            "message": f"Connected OK. SQL Server version: {row[0]}",
            "provider": "sqlserver",
        }
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
            SELECT TABLE_NAME
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_TYPE = 'BASE TABLE'
            ORDER BY TABLE_NAME
        """)
        tables = [row[0] for row in cursor.fetchall()]

        cursor.execute("""
            SELECT TABLE_NAME
            FROM INFORMATION_SCHEMA.VIEWS
            ORDER BY TABLE_NAME
        """)
        views = [row[0] for row in cursor.fetchall()]

        cursor.execute("""
            SELECT ROUTINE_NAME
            FROM INFORMATION_SCHEMA.ROUTINES
            WHERE ROUTINE_TYPE = 'PROCEDURE'
            ORDER BY ROUTINE_NAME
        """)
        procedures = [row[0] for row in cursor.fetchall()]

        return [
            {"key": "tables", "label": "Tables", "items": [{"name": n, "subtitle": "table", "objectType": "table"} for n in tables]},
            {"key": "views", "label": "Views", "items": [{"name": n, "subtitle": "view", "objectType": "view"} for n in views]},
            {"key": "procedures", "label": "Procedures", "items": [{"name": n, "subtitle": "procedure", "objectType": "procedure"} for n in procedures]},
        ]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_object_structure(payload, object_name: str, object_type: str):
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT
                c.COLUMN_NAME,
                c.DATA_TYPE,
                c.IS_NULLABLE,
                CASE WHEN tc.CONSTRAINT_TYPE = 'PRIMARY KEY' THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
            FROM INFORMATION_SCHEMA.COLUMNS c
            LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                ON c.TABLE_SCHEMA = kcu.TABLE_SCHEMA
                AND c.TABLE_NAME = kcu.TABLE_NAME
                AND c.COLUMN_NAME = kcu.COLUMN_NAME
            LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
                ON kcu.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
                AND kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
                AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
            WHERE c.TABLE_NAME = %s
            ORDER BY c.ORDINAL_POSITION
        """, (object_name,))

        return [
            {
                "name": row[0],
                "dataType": row[1],
                "isNullable": str(row[2]).upper() == "YES",
                "flag": "PK" if row[3] else None,
            }
            for row in cursor.fetchall()
        ]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_sqlserver_object_preview(payload, object_name: str, object_type: str, limit: int):
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        safe_object_name = object_name.replace("]", "").replace("[", "")
        cursor.execute(f"SELECT TOP {int(limit)} * FROM [{safe_object_name}]")
        columns = [column[0] for column in cursor.description]
        rows = [[_serialize_value(value) for value in row] for row in cursor.fetchall()]
        return columns, rows
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def execute_sqlserver_query(payload, sql: str, limit: int):
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute(sql)
        if cursor.description is None:
            return [], []
        columns = [column[0] for column in cursor.description]
        rows = []
        for index, row in enumerate(cursor.fetchall()):
            if index >= limit:
                break
            rows.append([_serialize_value(value) for value in row])
        return columns, rows
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()
