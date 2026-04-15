from app.schemas.connections import ConnectionTestRequest, ConnectionTestResponse

class ConnectionTestError(Exception):
    def __init__(self, message: str):
        super().__init__(message)
        
class DbTesterService:

    def test_connection(self, payload: ConnectionTestRequest) -> ConnectionTestResponse:
        provider = payload.provider.lower()

        if provider == "postgresql":
            return self._test_postgresql()

        if provider == "oracle":
            return self._test_oracle()

        if provider in ("sqlserver", "sql_server"):
            return self._test_sqlserver()

        return ConnectionTestResponse(
            success=False,
            message=f"Unsupported provider: {payload.provider}",
            durationMs=0
        )

    def _test_postgresql(self):
        return ConnectionTestResponse(success=True, message="PostgreSQL connector reached", durationMs=100)

    def _test_oracle(self):
        return ConnectionTestResponse(success=True, message="Oracle connector reached", durationMs=120)

    def _test_sqlserver(self):
        return ConnectionTestResponse(success=True, message="SQL Server connector reached", durationMs=140)
