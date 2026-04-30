def test_oracle_connection(payload) -> dict:
    target = payload.serviceName or payload.sid or "unknown"
    return {
        "success": True,
        "message": f"Oracle connector selected for host={payload.host}, target={target}. DEMO MODE.",
        "provider": "oracle",
        "mode": "demo",
    }


def build_oracle_default_query(object_name: str, object_type: str, schema_name: str | None = None) -> str:
    prefix = f"{schema_name}." if schema_name else ""
    if (object_type or "").lower() == "procedure":
        return f"BEGIN {prefix}{object_name}; END;"
    return f"SELECT *\nFROM {prefix}{object_name}\nFETCH FIRST 50 ROWS ONLY;"


def get_oracle_objects(payload):
    return [
        {
            "key": "tables",
            "label": "Tables",
            "items": [
                {
                    "name": "CUSTOMERS_DEMO",
                    "schemaName": "DEMO",
                    "subtitle": "DEMO · table · fake metadata",
                    "objectType": "table",
                    "defaultQuery": build_oracle_default_query("CUSTOMERS_DEMO", "table", "DEMO"),
                    "isDemo": True,
                }
            ],
        },
        {
            "key": "views",
            "label": "Views",
            "items": [
                {
                    "name": "V_CUSTOMERS_DEMO",
                    "schemaName": "DEMO",
                    "subtitle": "DEMO · view · fake metadata",
                    "objectType": "view",
                    "defaultQuery": build_oracle_default_query("V_CUSTOMERS_DEMO", "view", "DEMO"),
                    "isDemo": True,
                }
            ],
        },
        {
            "key": "procedures",
            "label": "Procedures",
            "items": [
                {
                    "name": "SP_CUSTOMERS_DEMO",
                    "schemaName": "DEMO",
                    "subtitle": "DEMO · procedure · fake metadata",
                    "objectType": "procedure",
                    "defaultQuery": build_oracle_default_query("SP_CUSTOMERS_DEMO", "procedure", "DEMO"),
                    "isDemo": True,
                }
            ],
        },
    ]


def get_oracle_object_structure(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() == "procedure":
        return []
    return [
        {"name": "ID", "dataType": "NUMBER", "isNullable": False, "flag": "PK"},
        {"name": "DESCRIPTION", "dataType": "VARCHAR2(200)", "isNullable": True, "flag": None},
    ]


def get_oracle_object_preview(payload, object_name: str, object_type: str, limit: int, schema_name: str | None = None):
    if (object_type or "").lower() == "procedure":
        return [], []
    return ["ID", "DESCRIPTION"], [[1, "Oracle demo row"]]


def get_oracle_object_definition(payload, object_name: str, object_type: str, schema_name: str | None = None):
    return "-- Oracle connector is currently in DEMO MODE. Real metadata integration pending."


def get_oracle_object_parameters(payload, object_name: str, object_type: str, schema_name: str | None = None):
    if (object_type or "").lower() != "procedure":
        return []
    return [
        {"name": "P_ID", "dataType": "NUMBER", "direction": "IN", "hasDefault": False},
    ]


def execute_oracle_query(payload, sql: str, limit: int):
    return ["message"], [["Oracle connector is currently in DEMO MODE. Query was not executed."]]
