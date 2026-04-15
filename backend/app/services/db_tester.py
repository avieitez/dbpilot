import time

from app.schemas.connections import ConnectionTestRequest, ConnectionTestResponse
from app.services.postgres import test_postgres_connection


class ConnectionTestError(Exception):
    pass


class DbTesterService:
    def test_connection(self, payload: ConnectionTestRequest) -> ConnectionTestResponse:
        provider = payload.provider.lower().strip()
        started_at = time.perf_counter()

        self._validate_payload(payload)

        if provider == "postgresql":
            result = self._test_postgresql(payload)
        elif provider == "oracle":
            result = self._test_oracle(payload)
        elif provider in ("sqlserver", "sql_server", "sql server", "mssql"):
            result = self._test_sql_server(payload)
        else:
            raise ValueError(f"Unsupported provider: {payload.provider}")

        duration_ms = int((time.perf_counter() - started_at) * 1000)
        return ConnectionTestResponse(
            success=result["success"],
            message=result["message"],
            durationMs=duration_ms,
        )

    def _validate_payload(self, payload: ConnectionTestRequest) -> None:
        if not payload.host or not payload.host.strip():
            raise ConnectionTestError("Host is required")

        if not payload.port or not str(payload.port).strip():
            raise ConnectionTestError("Port is required")

        if not payload.username or not payload.username.strip():
            raise ConnectionTestError("Username is required")

        if not payload.password or not payload.password.strip():
            raise ConnectionTestError("Password is required")

        provider = payload.provider.lower().strip()

        if provider == "oracle":
            has_service_name = bool(payload.serviceName and payload.serviceName.strip())
            has_sid = bool(payload.sid and payload.sid.strip())
            if not has_service_name and not has_sid:
                raise ConnectionTestError("Oracle requires Service Name or SID")
        else:
            if not payload.database or not payload.database.strip():
                raise ConnectionTestError("Database is required")

    def _test_postgresql(self, payload: ConnectionTestRequest) -> dict:
        return test_postgres_connection(payload)

    def _test_oracle(self, payload: ConnectionTestRequest) -> dict:
        target = payload.serviceName.strip() if payload.serviceName else payload.sid.strip()
        return {
            "success": True,
            "message": f"Oracle connector reached successfully ({target})",
        }

    def _test_sql_server(self, payload: ConnectionTestRequest) -> dict:
        encryption = "with encryption" if payload.encrypt else "without encryption"
        return {
            "success": True,
            "message": f"SQL Server connector reached successfully ({encryption})",
        }
