from app.schemas.connections import (
    ConnectionTestRequest,
    DbObjectListResponse,
    DbObjectStructureResponse,
    DbObjectPreviewResponse,
    DbObjectDefinitionResponse,
    DbObjectParametersResponse,
)
from app.core.db_connectors.postgres import (
    get_postgres_objects,
    get_postgres_object_structure,
    get_postgres_object_preview,
    execute_postgres_query,
    get_postgres_object_definition,
    get_postgres_object_parameters,
)
from app.core.db_connectors.sqlserver import (
    get_sqlserver_objects,
    get_sqlserver_object_structure,
    get_sqlserver_object_preview,
    execute_sqlserver_query,
    get_sqlserver_object_definition,
    get_sqlserver_object_parameters,
)
from app.core.db_connectors.oracle import (
    get_oracle_objects,
    get_oracle_object_structure,
    get_oracle_object_preview,
    execute_oracle_query,
    get_oracle_object_definition,
    get_oracle_object_parameters,
)

class DbExplorerError(Exception):
    pass

class DbExplorerService:
    def get_objects(self, payload: ConnectionTestRequest) -> DbObjectListResponse:
        self._validate_connection_payload(payload, allow_demo_oracle=True)
        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            groups = get_postgres_objects(payload)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            groups = get_sqlserver_objects(payload)
        elif provider == "oracle":
            groups = get_oracle_objects(payload)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")
        return DbObjectListResponse(provider=provider, groups=groups)

    def get_object_structure(self, payload, object_name, object_type, schema_name=None):
        self._validate_connection_payload(payload, allow_demo_oracle=True)
        self._validate_object(object_name, object_type)
        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            columns = get_postgres_object_structure(payload, object_name, object_type, schema_name)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            columns = get_sqlserver_object_structure(payload, object_name, object_type, schema_name)
        elif provider == "oracle":
            columns = get_oracle_object_structure(payload, object_name, object_type, schema_name)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")
        return DbObjectStructureResponse(provider=provider, objectName=object_name, objectType=object_type, schemaName=schema_name, columns=columns)

    def get_object_preview(self, payload, object_name, object_type, limit, schema_name=None):
        self._validate_connection_payload(payload, allow_demo_oracle=True)
        self._validate_object(object_name, object_type)
        self._validate_limit(limit)
        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            columns, rows = get_postgres_object_preview(payload, object_name, object_type, limit, schema_name)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            columns, rows = get_sqlserver_object_preview(payload, object_name, object_type, limit, schema_name)
        elif provider == "oracle":
            columns, rows = get_oracle_object_preview(payload, object_name, object_type, limit, schema_name)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")
        return DbObjectPreviewResponse(provider=provider, objectName=object_name, objectType=object_type, schemaName=schema_name, columns=columns, rows=rows, rowCount=len(rows))

    def get_object_definition(self, payload, object_name, object_type, schema_name=None):
        self._validate_connection_payload(payload, allow_demo_oracle=True)
        self._validate_object(object_name, object_type)
        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            definition = get_postgres_object_definition(payload, object_name, object_type, schema_name)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            definition = get_sqlserver_object_definition(payload, object_name, object_type, schema_name)
        elif provider == "oracle":
            definition = get_oracle_object_definition(payload, object_name, object_type, schema_name)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")
        return DbObjectDefinitionResponse(provider=provider, objectName=object_name, objectType=object_type, schemaName=schema_name, definition=definition)

    def get_object_parameters(self, payload, object_name, object_type, schema_name=None):
        self._validate_connection_payload(payload, allow_demo_oracle=True)
        self._validate_object(object_name, object_type)
        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            parameters = get_postgres_object_parameters(payload, object_name, object_type, schema_name)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            parameters = get_sqlserver_object_parameters(payload, object_name, object_type, schema_name)
        elif provider == "oracle":
            parameters = get_oracle_object_parameters(payload, object_name, object_type, schema_name)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")
        return DbObjectParametersResponse(provider=provider, objectName=object_name, objectType=object_type, schemaName=schema_name, parameters=parameters)

    def execute_query(self, payload: ConnectionTestRequest, sql: str, limit: int, allow_data_modification: bool = False, timeout_seconds: int = 30):
        self._validate_connection_payload(payload, allow_demo_oracle=True)
        self._validate_limit(limit, max_limit=500)
        self._validate_timeout(timeout_seconds)
        clean_sql = (sql or "").strip()
        if not clean_sql:
            raise DbExplorerError("SQL is required")
        first_word = clean_sql.split()[0].lower()
        is_data_modification = first_word in {"insert", "update", "delete", "merge", "create", "alter", "drop", "truncate", "exec", "execute", "call"}
        if is_data_modification and not allow_data_modification:
            raise DbExplorerError("Data modification is disabled. Turn Safe Mode OFF to run this statement.")
        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            return execute_postgres_query(payload, clean_sql, limit, timeout_seconds)
        if provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            return execute_sqlserver_query(payload, clean_sql, limit, timeout_seconds)
        if provider == "oracle":
            return execute_oracle_query(payload, clean_sql, limit)
        raise ValueError(f"Unsupported provider: {payload.provider}")

    def _validate_connection_payload(self, payload: ConnectionTestRequest, allow_demo_oracle: bool = False) -> None:
        provider = (payload.provider or "").lower().strip()
        if allow_demo_oracle and provider == "oracle":
            return
        if not payload.host or not payload.host.strip():
            raise DbExplorerError("Host is required")
        if not payload.port or not str(payload.port).strip():
            raise DbExplorerError("Port is required")
        if not payload.username or not payload.username.strip():
            raise DbExplorerError("Username is required")
        if not payload.password or not payload.password.strip():
            raise DbExplorerError("Password is required")
        if not payload.database or not payload.database.strip():
            raise DbExplorerError("Database is required")

    def _validate_object(self, object_name: str, object_type: str) -> None:
        if not object_name or not object_name.strip():
            raise DbExplorerError("Object name is required")
        if not object_type or not object_type.strip():
            raise DbExplorerError("Object type is required")

    def _validate_limit(self, limit: int, max_limit: int = 200) -> None:
        if limit < 1 or limit > max_limit:
            raise DbExplorerError(f"Limit must be between 1 and {max_limit}")

    def _validate_timeout(self, timeout_seconds: int) -> None:
        if timeout_seconds < 5 or timeout_seconds > 120:
            raise DbExplorerError("Timeout must be between 5 and 120 seconds")
