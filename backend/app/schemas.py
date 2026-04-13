from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class Provider(str, Enum):
    postgresql = "postgresql"
    sqlserver = "sqlserver"
    oracle = "oracle"


class ConnectionTestRequest(BaseModel):
    name: str = Field(..., min_length=1)
    provider: Provider
    host: str = Field(..., min_length=1)
    port: int = Field(..., ge=1, le=65535)
    username: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)
    database: str = ""
    service_name: Optional[str] = None
    sid: Optional[str] = None
    encrypt: bool = False
    trust_server_certificate: bool = False

    @model_validator(mode="after")
    def validate_provider_specific_fields(self):
        if self.provider in {Provider.postgresql, Provider.sqlserver} and not self.database:
            raise ValueError("database is required for PostgreSQL and SQL Server")
        if self.provider == Provider.oracle and not (self.service_name or self.sid):
            raise ValueError("service_name or sid is required for Oracle")
        return self


class ConnectionTestResponse(BaseModel):
    success: bool
    message: str
    duration_ms: Optional[int] = None
