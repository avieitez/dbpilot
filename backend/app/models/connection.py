from datetime import datetime
from pydantic import BaseModel


class ConnectionRecord(BaseModel):
    id: str
    name: str
    provider: str
    host: str
    port: int
    database: str
    username: str
    encrypted_password: str
    created_at: datetime
