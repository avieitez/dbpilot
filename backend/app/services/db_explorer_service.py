from app.schemas.connections import (
    ConnectionTestRequest,
    DbObjectListResponse,
    DbObjectStructureResponse,
    DbObjectPreviewResponse,
)
from app.core.db_connectors.postgres import (
    get_postgres_objects,
    get_postgres_object_structure,
    get_postgres_object_preview,
    execute_postgres_query,
)
from app.core.db_connectors.sqlserver import (
    get_sqlserver_objects,
    get_sqlserver_object_structure,
    get_sqlserver_object_preview,
    execute_sqlserver_query,
)


class DbExplorerError(Exception):
    pass


class DbExplorerService:
    def get_objects(self, payload: ConnectionTestRequest) -> DbObjectListResponse:
        self._validate_connection_payload(payload)
        provider = payload.provider.lower().strip()

        if provider == "postgresql":
            groups = get_postgres_objects(payload)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            groups = get_sqlserver_objects(payload)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")

        return DbObjectListResponse(provider=provider, groups=groups)

    def get_object_structure(
        self,
        payload: ConnectionTestRequest,
        object_name: str,
        object_type: str,
    ) -> DbObjectStructureResponse:
        self._validate_connection_payload(payload)
        self._validate_object(object_name, object_type)
        provider = payload.provider.lower().strip()

        if provider == "postgresql":
            columns = get_postgres_object_structure(payload, object_name, object_type)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            columns = get_sqlserver_object_structure(payload, object_name, object_type)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")

        return DbObjectStructureResponse(
            provider=provider,
            objectName=object_name,
            objectType=object_type,
            columns=columns,
        )

    def get_object_preview(
        self,
        payload: ConnectionTestRequest,
        object_name: str,
        object_type: str,
        limit: int,
    ) -> DbObjectPreviewResponse:
        self._validate_connection_payload(payload)
        self._validate_object(object_name, object_type)
        self._validate_limit(limit)
        provider = payload.provider.lower().strip()

        if provider == "postgresql":
            columns, rows = get_postgres_object_preview(payload, object_name, object_type, limit)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            columns, rows = get_sqlserver_object_preview(payload, object_name, object_type, limit)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")

        return DbObjectPreviewResponse(
            provider=provider,
            objectName=object_name,
            objectType=object_type,
            columns=columns,
            rows=rows,
            rowCount=len(rows),
        )

    def execute_query(self, payload: ConnectionTestRequest, sql: str, limit: int, allow_data_modification: bool = False):
        self._validate_connection_payload(payload)
        self._validate_limit(limit, max_limit=500)
        clean_sql = (sql or "").strip()

        if not clean_sql:
            raise DbExplorerError("SQL is required")

        first_word = clean_sql.split()[0].lower()
        data_modification_statements = {
            "insert", "update", "delete", "merge",
            "create", "alter", "drop", "truncate",
            "exec", "execute",
        }

        if first_word in data_modification_statements and not allow_data_modification:
            raise DbExplorerError("Data modification is disabled. Turn Safe Mode OFF to run this statement.")

        if not clean_sql.lower().startswith("select"):
            raise DbExplorerError("Por seguridad, por ahora solo se permiten consultas SELECT.")

        provider = payload.provider.lower().strip()
        if provider == "postgresql":
            return execute_postgres_query(payload, clean_sql, limit)
        if provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            return execute_sqlserver_query(payload, clean_sql, limit)

        raise ValueError(f"Unsupported provider: {payload.provider}")

    def _validate_connection_payload(self, payload: ConnectionTestRequest) -> None:
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
