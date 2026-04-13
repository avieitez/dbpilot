from datetime import datetime
from uuid import uuid4

from app.core.security import CredentialCipher
from app.models.connection import ConnectionRecord
from app.schemas.connections import CreateConnectionRequest, CreateConnectionResponse

class ConnectionService:
    def __init__(self, cipher: CredentialCipher) -> None:
        self._cipher = cipher
        self._memory_store: list[ConnectionRecord] = []

    def create_connection(self, payload: CreateConnectionRequest) -> CreateConnectionResponse:
        encrypted = self._cipher.encrypt(payload.password)

        record = ConnectionRecord(
            id=str(uuid4()),
            name=payload.name,
            provider=payload.provider,
            host=payload.host,
            port=payload.port,
            database=payload.database,
            username=payload.username,
            encrypted_password=encrypted,
            created_at=datetime.utcnow(),
        )
        self._memory_store.append(record)

        return CreateConnectionResponse(
            id=record.id,
            name=record.name,
            provider=payload.provider,
            host=record.host,
            port=record.port,
            database=record.database,
            username=record.username,
            encrypted_password_preview=f'{encrypted[:12]}...',
        )
