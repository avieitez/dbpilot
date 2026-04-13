from __future__ import annotations

import time
from contextlib import closing

import oracledb
import psycopg2
from psycopg2 import OperationalError as PostgresError

try:
    import pyodbc
except ImportError:  # pragma: no cover
    pyodbc = None

from ..schemas import ConnectionTestRequest, ConnectionTestResponse, Provider


class ConnectionTestError(Exception):
    pass


class DbTesterService:
    def test_connection(self, request: ConnectionTestRequest) -> ConnectionTestResponse:
        start = time.perf_counter()

        if request.provider == Provider.postgresql:
            self._test_postgresql(request)
        elif request.provider == Provider.sqlserver:
            self._test_sqlserver(request)
        elif request.provider == Provider.oracle:
            self._test_oracle(request)
        else:  # pragma: no cover
            raise ConnectionTestError(f"Unsupported provider: {request.provider}")

        duration_ms = int((time.perf_counter() - start) * 1000)
        return ConnectionTestResponse(
            success=True,
            message=f"{request.provider.value} connection successful",
            duration_ms=duration_ms,
        )

    def _test_postgresql(self, request: ConnectionTestRequest) -> None:
        try:
            with closing(
                psycopg2.connect(
                    host=request.host,
                    port=request.port,
                    dbname=request.database,
                    user=request.username,
                    password=request.password,
                    connect_timeout=5,
                )
            ) as connection:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
        except PostgresError as exc:
            raise ConnectionTestError(str(exc)) from exc

    def _test_sqlserver(self, request: ConnectionTestRequest) -> None:
        if pyodbc is None:
            raise ConnectionTestError(
                "pyodbc is not installed. Run `pip install pyodbc` and install the Microsoft ODBC Driver 18 for SQL Server."
            )

        encrypt = "yes" if request.encrypt else "no"
        trust = "yes" if request.trust_server_certificate else "no"
        connection_string = (
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={request.host},{request.port};"
            f"DATABASE={request.database};"
            f"UID={request.username};"
            f"PWD={request.password};"
            f"Encrypt={encrypt};"
            f"TrustServerCertificate={trust};"
            "Connection Timeout=5;"
        )

        try:
            with closing(pyodbc.connect(connection_string)) as connection:
                with closing(connection.cursor()) as cursor:
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
        except Exception as exc:
            raise ConnectionTestError(str(exc)) from exc

    def _test_oracle(self, request: ConnectionTestRequest) -> None:
        try:
            if request.service_name:
                dsn = oracledb.makedsn(
                    request.host,
                    request.port,
                    service_name=request.service_name,
                )
            else:
                dsn = oracledb.makedsn(
                    request.host,
                    request.port,
                    sid=request.sid,
                )

            with closing(
                oracledb.connect(
                    user=request.username,
                    password=request.password,
                    dsn=dsn,
                )
            ) as connection:
                with closing(connection.cursor()) as cursor:
                    cursor.execute("SELECT 1 FROM dual")
                    cursor.fetchone()
        except Exception as exc:
            raise ConnectionTestError(str(exc)) from exc
