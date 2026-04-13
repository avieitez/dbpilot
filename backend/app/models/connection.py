from pydantic import BaseModel, Field
from typing import Literal


class ConnectionCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    provider: Literal["sqlserver", "oracle", "postgresql"]
    host: str = Field(min_length=1, max_length=255)
    port: int = Field(gt=0, lt=65536)
    database: str = Field(min_length=1, max_length=100)
    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=255)


class ConnectionResponse(BaseModel):
    id: str
    name: str
    provider: str
    host: str
    port: int
    database: str
    username: str
    encrypted_password: str
