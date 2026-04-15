from __future__ import annotations

import time

from app.core.db_connectors.oracle import test_oracle_connection
from app.core.db_connectors.postgres import test_postgres_connection
from app.core.db_connectors.sqlserver import test_sqlserver_connection
from app.schemas.connections import ConnectionTestRequest, ConnectionTestResponse, Provider


class ConnectionTestError(Exception):
    pass


class DbTesterService:
    def test_connection(self, request: ConnectionTestRequest) -> ConnectionTestResponse:
        start = time.perf_counter()

        if request.provider == Provider.postgresql:
            result = test_postgres_connection(request)
        elif request.provider == Provider.sqlserver:
            result = test_sqlserver_connection(request)
        elif request.provider == Provider.oracle:
            result = test_oracle_connection(request)
        else:
            raise ConnectionTestError(f"Unsupported provider: {request.provider}")

        duration_ms = int((time.perf_counter() - start) * 1000)

        return ConnectionTestResponse(
            success=result["success"],
            message=result["message"],
            provider=result["provider"],
            duration_ms=duration_ms,
        )
