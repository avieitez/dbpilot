from pydantic import BaseModel

class ConnectionTestRequest(BaseModel):
    name: str
    provider: str
    host: str
    port: str
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
