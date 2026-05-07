from datetime import datetime
from pydantic import BaseModel


class ConnectionRecord(BaseModel):
    id: str
    name: str
    provider: str
    host: str
    port: int
    database: str | None = None
    serviceName: str | None = None
    sid: str | None = None
    username: str
    encrypted_password: str
    created_at: datetime
