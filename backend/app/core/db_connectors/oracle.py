import re

import oracledb


def _clean(value: str | None) -> str:
    return (value or "").strip()


def _owner(payload, schema_name: str | None = None) -> str:
    return _clean(schema_name or payload.username).upper()


def _dsn(payload) -> str:
    host = _clean(payload.host)
    port = int(payload.port or 1521)
    service_name = _clean(getattr(payload, "serviceName", None))
    sid = _clean(getattr(payload, "sid", None))

    if service_name:
        protocol = "tcps" if port == 2484 else "tcp"
        return f"{protocol}://{host}:{port}/{service_name}"

    if sid:
        return oracledb.makedsn(host, port, sid=sid)

    database = _clean(getattr(payload, "database", None))
    if database:
        protocol = "tcps" if port == 2484 else "tcp"
        return f"{protocol}://{host}:{port}/{database}"

    raise ValueError("Oracle requires serviceName, SID, or database/service value")


def _connect(payload, timeout_seconds: int = 30):
    conn = oracledb.connect(
        user=payload.username,
        password=payload.password,
        dsn=_dsn(payload),
    )
    conn.call_timeout = max(1, int(timeout_seconds or 30)) * 1000
    return conn


def _serialize_value(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def _quote_identifier(value: str) -> str:
    clean = (value or "").replace('"', '""').strip()
    return f'"{clean}"'


def _qualified_name(object_name: str, schema_name: str | None = None, payload=None) -> str:
    owner = _owner(payload, schema_name) if payload is not None else _clean(schema_name).upper()
    name = _clean(object_name).upper()
    return f"{_quote_identifier(owner)}.{_quote_identifier(name)}" if owner else _quote_identifier(name)


def _format_data_type(data_type, data_length, precision, scale):
    clean_type = (data_type or "").upper()
    if clean_type in {"CHAR", "NCHAR", "VARCHAR2", "NVARCHAR2", "RAW"} and data_length:
        return f"{clean_type}({data_length})"
    if clean_type == "NUMBER":
        if precision is not None and scale is not None:
            return f"NUMBER({precision},{scale})"
        if precision is not None:
            return f"NUMBER({precision})"
        return "NUMBER"
    return clean_type


def test_oracle_connection(payload) -> dict:
    conn = None
    cursor = None
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM dual")
        cursor.fetchone()
        target = _clean(getattr(payload, "serviceName", None)) or _clean(getattr(payload, "sid", None)) or _clean(getattr(payload, "database", None))
        return {"success": True, "message": f"Oracle connection successful. Target: {target}", "provider": "oracle", "mode": "real"}
    except Exception as e:
        return {"success": False, "message": str(e), "provider": "oracle", "mode": "real"}
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def build_oracle_default_query(object_name: str, object_type: str, schema_name: str | None = None) -> str:
    prefix = f'{_quote_identifier(_clean(schema_name).upper())}.' if schema_name else ""
    name = _quote_identifier(_clean(object_name).upper())
    clean_type = (object_type or "").lower()

    if clean_type in {"procedure", "function"}:
        return f"BEGIN\n  {prefix}{name};\nEND;"
    if clean_type == "package":
        return f"-- Package {prefix}{name}. Open definition to inspect package source."
    if clean_type == "trigger":
        return f"-- Trigger {prefix}{name}. Open definition to inspect trigger source."
    if clean_type == "sequence":
        return f"SELECT {prefix}{name}.NEXTVAL AS NEXT_VALUE\nFROM dual;"
    return f"SELECT *\nFROM {prefix}{name};"


def get_oracle_objects(payload):
    conn = None
    cursor = None
    owner = _owner(payload)
    try:
        conn = _connect(payload)
        cursor = conn.cursor()

        queries = {
            "tables": ("Tables", "table", "SELECT owner, table_name FROM all_tables WHERE owner = :owner ORDER BY table_name"),
            "views": ("Views", "view", "SELECT owner, view_name FROM all_views WHERE owner = :owner ORDER BY view_name"),
            "procedures": ("Procedures", "procedure", "SELECT owner, object_name FROM all_objects WHERE owner = :owner AND object_type = 'PROCEDURE' ORDER BY object_name"),
            "functions": ("Functions", "function", "SELECT owner, object_name FROM all_objects WHERE owner = :owner AND object_type = 'FUNCTION' ORDER BY object_name"),
            "packages": ("Packages", "package", "SELECT owner, object_name FROM all_objects WHERE owner = :owner AND object_type = 'PACKAGE' ORDER BY object_name"),
            "triggers": ("Triggers", "trigger", "SELECT owner, trigger_name FROM all_triggers WHERE owner = :owner ORDER BY trigger_name"),
            "sequences": ("Sequences", "sequence", "SELECT sequence_owner, sequence_name FROM all_sequences WHERE sequence_owner = :owner ORDER BY sequence_name"),
        }

        def item(row, object_type):
            schema, name = row[0], row[1]
            return {
                "name": name,
                "schemaName": schema,
                "subtitle": f"{schema} · {object_type}",
                "objectType": object_type,
                "defaultQuery": build_oracle_default_query(name, object_type, schema),
                "isDemo": False,
            }

        groups = []
        for key, (label, object_type, query) in queries.items():
            cursor.execute(query, owner=owner)
            rows = cursor.fetchall()
            groups.append({"key": key, "label": label, "items": [item(row, object_type) for row in rows]})
        return groups
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_oracle_object_structure(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() not in {"table", "view"}:
        return []
    conn = None
    cursor = None
    owner = _owner(payload, schema_name)
    name = _clean(object_name).upper()
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT c.column_name,
                   c.data_type,
                   c.data_length,
                   c.data_precision,
                   c.data_scale,
                   c.nullable,
                   CASE WHEN pk.column_name IS NOT NULL THEN 'PK' ELSE NULL END AS flag
            FROM all_tab_columns c
            LEFT JOIN (
                SELECT acc.owner, acc.table_name, acc.column_name
                FROM all_constraints ac
                INNER JOIN all_cons_columns acc
                    ON ac.owner = acc.owner
                   AND ac.constraint_name = acc.constraint_name
                   AND ac.table_name = acc.table_name
                WHERE ac.constraint_type = 'P'
            ) pk
              ON pk.owner = c.owner
             AND pk.table_name = c.table_name
             AND pk.column_name = c.column_name
            WHERE c.owner = :owner
              AND c.table_name = :name
            ORDER BY c.column_id
        """, owner=owner, name=name)
        return [
            {"name": row[0], "dataType": _format_data_type(row[1], row[2], row[3], row[4]), "isNullable": str(row[5]).upper() == "Y", "flag": row[6]}
            for row in cursor.fetchall()
        ]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_oracle_object_preview(payload, object_name: str, object_type: str, limit: int, schema_name: str | None = None):
    if (object_type or "").lower() not in {"table", "view"}:
        return [], []
    conn = None
    cursor = None
    clean_limit = max(1, min(int(limit), 5000))
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        query = f"SELECT * FROM {_qualified_name(object_name, schema_name, payload)} FETCH FIRST {clean_limit} ROWS ONLY"
        cursor.execute(query)
        columns = [desc[0] for desc in cursor.description]
        rows = [[_serialize_value(value) for value in row] for row in cursor.fetchall()]
        return columns, rows
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_oracle_object_definition(payload, object_name: str, object_type: str, schema_name: str | None = None):
    conn = None
    cursor = None
    owner = _owner(payload, schema_name)
    name = _clean(object_name).upper()
    clean_type = (object_type or "").lower()
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        if clean_type == "view":
            cursor.execute("SELECT text FROM all_views WHERE owner = :owner AND view_name = :name", owner=owner, name=name)
            row = cursor.fetchone()
            return row[0] if row else None
        if clean_type in {"procedure", "function", "package", "trigger"}:
            source_type = clean_type.upper()
            cursor.execute("""
                SELECT text
                FROM all_source
                WHERE owner = :owner
                  AND name = :name
                  AND type = :source_type
                ORDER BY line
            """, owner=owner, name=name, source_type=source_type)
            return "".join(row[0] for row in cursor.fetchall()) or None
        if clean_type == "sequence":
            cursor.execute("""
                SELECT 'CREATE SEQUENCE ' || sequence_owner || '.' || sequence_name ||
                       ' MINVALUE ' || min_value ||
                       ' MAXVALUE ' || max_value ||
                       ' INCREMENT BY ' || increment_by ||
                       ' START WITH ' || last_number
                FROM all_sequences
                WHERE sequence_owner = :owner AND sequence_name = :name
            """, owner=owner, name=name)
            row = cursor.fetchone()
            return row[0] if row else None
        return None
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def get_oracle_object_parameters(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() not in {"procedure", "function"}:
        return []
    conn = None
    cursor = None
    owner = _owner(payload, schema_name)
    name = _clean(object_name).upper()
    try:
        conn = _connect(payload)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT argument_name, data_type, in_out, defaulted
            FROM all_arguments
            WHERE owner = :owner
              AND object_name = :name
            ORDER BY position
        """, owner=owner, name=name)
        return [
            {"name": row[0] or "RETURN", "dataType": row[1] or "", "direction": row[2] or "OUT", "hasDefault": str(row[3]).upper() == "Y"}
            for row in cursor.fetchall()
        ]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def _oracle_bind_names(sql: str) -> list[str]:
    clean = re.sub(r"'(?:''|[^'])*'", "''", sql or "")
    names = re.findall(r"(?<!:):([A-Za-z][A-Za-z0-9_]*)", clean)
    return list(dict.fromkeys(names))


def _is_auto_cursor_bind(name: str) -> bool:
    return name.upper() in {"RC", "CURSOR", "RESULT", "RESULTSET", "RESULT_SET", "OUT_CURSOR", "P_CURSOR"}


def _fetch_cursor_var(cursor_var, clean_limit: int):
    result_cursor = cursor_var.getvalue()
    if result_cursor is None:
        return ["message"], [["Procedure executed successfully."]]
    return _fetch_oracle_cursor(result_cursor, clean_limit)


def _fetch_oracle_cursor(result_cursor, clean_limit: int):
    try:
        if result_cursor.description is None:
            return ["message"], [["Procedure executed successfully."]]
        columns = [desc[0] for desc in result_cursor.description]
        rows = [[_serialize_value(value) for value in row] for row in result_cursor.fetchmany(clean_limit)]
        return columns, rows
    finally:
        result_cursor.close()


def _fetch_implicit_results(cursor, clean_limit: int):
    if not hasattr(cursor, "getimplicitresults"):
        return None
    implicit_results = cursor.getimplicitresults()
    if not implicit_results:
        return None
    for result_cursor in implicit_results:
        if result_cursor.description is not None:
            return _fetch_oracle_cursor(result_cursor, clean_limit)
        result_cursor.close()
    return ["message"], [["Procedure executed successfully."]]


def execute_oracle_query(payload, sql: str, limit: int, timeout_seconds: int = 30):
    conn = None
    cursor = None
    clean_limit = max(1, min(int(limit), 5000))
    try:
        conn = _connect(payload, timeout_seconds)
        cursor = conn.cursor()
        bind_names = _oracle_bind_names(sql)
        auto_cursor_binds = {
            name: cursor.var(oracledb.CURSOR)
            for name in bind_names
            if _is_auto_cursor_bind(name)
        }
        if auto_cursor_binds and len(auto_cursor_binds) == len(bind_names):
            cursor.execute(sql, auto_cursor_binds)
            conn.commit()
            return _fetch_cursor_var(next(iter(auto_cursor_binds.values())), clean_limit)

        cursor.execute(sql)
        if cursor.description is None:
            implicit_result = _fetch_implicit_results(cursor, clean_limit)
            if implicit_result is not None:
                conn.commit()
                return implicit_result
            affected = cursor.rowcount if cursor.rowcount is not None and cursor.rowcount >= 0 else 0
            conn.commit()
            return ["message"], [[f"Query executed successfully. Rows affected: {affected}"]]
        columns = [desc[0] for desc in cursor.description]
        rows = [[_serialize_value(value) for value in row] for row in cursor.fetchmany(clean_limit)]
        return columns, rows
    except oracledb.Error as exc:
        if conn is not None:
            conn.rollback()
        message = str(exc)
        if "DPY-4024" in message or "timeout" in message.lower():
            raise TimeoutError(f"Oracle query exceeded timeout of {timeout_seconds} seconds") from exc
        raise
    except Exception:
        if conn is not None:
            conn.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()
