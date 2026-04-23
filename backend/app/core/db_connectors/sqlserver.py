import pyodbc


def _connect(payload):
    database = payload.database or "master"
    conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        f"SERVER={payload.host},{payload.port};"
        f"DATABASE={database};"
        f"UID={payload.username};"
        f"PWD={payload.password};"
        f"Encrypt={'yes' if payload.encrypt else 'no'};"
        f"TrustServerCertificate={'yes' if payload.trustServerCertificate else 'no'};"
    )
    return pyodbc.connect(conn_str, timeout=10)


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
        return {
            "success": False,
            "message": str(e),
            "provider": "sqlserver",
        }
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

        cursor.execute(
            '''
            SELECT TABLE_NAME
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_TYPE = 'BASE TABLE'
            ORDER BY TABLE_NAME
            '''
        )
        tables = [row[0] for row in cursor.fetchall()]

        cursor.execute(
            '''
            SELECT TABLE_NAME
            FROM INFORMATION_SCHEMA.VIEWS
            ORDER BY TABLE_NAME
            '''
        )
        views = [row[0] for row in cursor.fetchall()]

        cursor.execute(
            '''
            SELECT ROUTINE_NAME
            FROM INFORMATION_SCHEMA.ROUTINES
            WHERE ROUTINE_TYPE = 'PROCEDURE'
            ORDER BY ROUTINE_NAME
            '''
        )
        procedures = [row[0] for row in cursor.fetchall()]

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
                "key": "procedures",
                "label": "Procedures",
                "items": [{"name": name, "subtitle": "procedure", "objectType": "procedure"} for name in procedures],
            },
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

        cursor.execute(
            '''
            SELECT
                c.COLUMN_NAME,
                c.DATA_TYPE,
                c.IS_NULLABLE,
                CASE WHEN kcu.COLUMN_NAME IS NOT NULL THEN 1 ELSE 0 END AS IS_PRIMARY_KEY
            FROM INFORMATION_SCHEMA.COLUMNS c
            LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                ON c.TABLE_NAME = kcu.TABLE_NAME
                AND c.COLUMN_NAME = kcu.COLUMN_NAME
            LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
                ON kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
                AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
            WHERE c.TABLE_NAME = ?
            ORDER BY c.ORDINAL_POSITION
            ''',
            object_name,
        )

        results = []
        for row in cursor.fetchall():
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

        sql = f"SELECT TOP {limit} * FROM [{object_name}]"
        cursor.execute(sql)

        columns = [column[0] for column in cursor.description]
        rows = [list(row) for row in cursor.fetchall()]
        return columns, rows

    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()
