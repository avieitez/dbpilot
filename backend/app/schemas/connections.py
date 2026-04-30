from typing import Any
from pydantic import BaseModel


class ConnectionTestRequest(BaseModel):
    name: str
    provider: str
    host: str
    port: int
    username: str
    password: str
    database: str | None = None
    serviceName: str | None = None
    sid: str | None = None
    encrypt: bool = False
    trustServerCertificate: bool = False


class ConnectionTestResponse(BaseModel):
    success: bool
    message: str
    durationMs: int | None = None
    provider: str | None = None
    mode: str | None = None


class DbObjectInfo(BaseModel):
    name: str
    subtitle: str
    objectType: str
    schemaName: str | None = None
    defaultQuery: str | None = None
    isDemo: bool = False


class DbObjectGroup(BaseModel):
    key: str
    label: str
    items: list[DbObjectInfo]


class DbObjectListResponse(BaseModel):
    provider: str
    groups: list[DbObjectGroup]


class DbColumnInfoResponse(BaseModel):
    name: str
    dataType: str
    isNullable: bool
    flag: str | None = None


class DbObjectStructureResponse(BaseModel):
    provider: str
    objectName: str
    objectType: str
    schemaName: str | None = None
    columns: list[DbColumnInfoResponse]


class DbObjectPreviewResponse(BaseModel):
    provider: str
    objectName: str
    objectType: str
    schemaName: str | None = None
    columns: list[str]
    rows: list[list[Any]]
    rowCount: int


class ObjectStructureRequest(BaseModel):
    connection: ConnectionTestRequest
    objectName: str
    objectType: str
    schemaName: str | None = None


class ObjectPreviewRequest(BaseModel):
    connection: ConnectionTestRequest
    objectName: str
    objectType: str
    schemaName: str | None = None
    limit: int = 50
