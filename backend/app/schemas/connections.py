from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Provider(str, Enum):
    postgresql = "postgresql"
    sqlserver = "sqlserver"
    oracle = "oracle"


class CreateConnectionRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=80)
    provider: Provider
    host: str = Field(..., min_length=1, max_length=255)
    port: int = Field(..., ge=1, le=65535)
    database: str = Field(..., min_length=1, max_length=255)
    username: str = Field(..., min_length=1, max_length=120)
    password: str = Field(..., min_length=1, max_length=255)


class CreateConnectionResponse(BaseModel):
    id: str
    name: str
    provider: Provider
    host: str
    port: int
    database: str
    username: str
    encrypted_password_preview: str


class ConnectionTestRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    name: str = Field(default="", min_length=0)
    provider: Provider
    host: str = Field(..., min_length=1)
    port: int = Field(..., ge=1, le=65535)
    username: str = Field(..., min_length=1)
    password: str = Field(..., min_length=1)
    database: str = ""
    service_name: Optional[str] = Field(default=None, alias="serviceName")
    sid: Optional[str] = None
    encrypt: bool = False
    trust_server_certificate: bool = Field(default=False, alias="trustServerCertificate")

    @model_validator(mode="after")
    def validate_provider_specific_fields(self):
        if self.provider in {Provider.postgresql, Provider.sqlserver} and not self.database:
            raise ValueError("database is required for PostgreSQL and SQL Server")
        if self.provider == Provider.oracle and not (self.service_name or self.sid):
            raise ValueError("serviceName or sid is required for Oracle")
        return self


class ConnectionTestResponse(BaseModel):
    success: bool
    message: str
    provider: str
    duration_ms: Optional[int] = None
