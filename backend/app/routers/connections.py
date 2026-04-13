from uuid import uuid4

from fastapi import APIRouter

from app.core.security import CredentialCipher
from app.models.connection import ConnectionCreate, ConnectionResponse

router = APIRouter(prefix="/connections", tags=["connections"])

FERNET_KEY = b"2qVxv5dNydg5RBI7fA4yp6k5uI8mTi1Ksz95jM0f3A8="
cipher = CredentialCipher(FERNET_KEY)


@router.post("", response_model=ConnectionResponse)
def create_connection(payload: ConnectionCreate) -> ConnectionResponse:
    return ConnectionResponse(
        id=str(uuid4()),
        name=payload.name,
        provider=payload.provider,
        host=payload.host,
        port=payload.port,
        database=payload.database,
        username=payload.username,
        encrypted_password=cipher.encrypt(payload.password),
    )
