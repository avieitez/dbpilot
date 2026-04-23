from app.schemas.connections import (
    ConnectionTestRequest,
    DbObjectGroup,
    DbObjectInfo,
    DbObjectListResponse,
    DbObjectStructureResponse,
    DbObjectPreviewResponse,
    DbColumnInfoResponse,
)
from app.core.db_connectors.postgres import (
    get_postgres_objects,
    get_postgres_object_structure,
    get_postgres_object_preview,
)
from app.core.db_connectors.sqlserver import (
    get_sqlserver_objects,
    get_sqlserver_object_structure,
    get_sqlserver_object_preview,
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
        if not object_name or not object_name.strip():
            raise DbExplorerError("Object name is required")
        if not object_type or not object_type.strip():
            raise DbExplorerError("Object type is required")

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
        if not object_name or not object_name.strip():
            raise DbExplorerError("Object name is required")
        if not object_type or not object_type.strip():
            raise DbExplorerError("Object type is required")
        if limit < 1 or limit > 200:
            raise DbExplorerError("Limit must be between 1 and 200")

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
