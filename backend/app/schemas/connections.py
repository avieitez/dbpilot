from typing import Literal
from pydantic import BaseModel, Field

ProviderType = Literal['sqlserver', 'oracle', 'postgresql']

class CreateConnectionRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    provider: ProviderType
    host: str = Field(min_length=1, max_length=255)
    port: int = Field(gt=0, lt=65536)
    database: str = Field(min_length=1, max_length=255)
    username: str = Field(min_length=1, max_length=120)
    password: str = Field(min_length=1, max_length=255)

class CreateConnectionResponse(BaseModel):
    id: str
    name: str
    provider: ProviderType
    host: str
    port: int
    database: str
    username: str
    encrypted_password_preview: str
