from dataclasses import dataclass

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from app.core.firebase_client import get_firebase_app


bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthenticatedUser:
    uid: str
    email: str | None
    email_verified: bool
    sign_in_provider: str | None


def authenticated_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase authentication is required.",
        )

    try:
        decoded_token = auth.verify_id_token(
            credentials.credentials,
            app=get_firebase_app(),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase ID token.",
        ) from exc

    uid = str(decoded_token.get("uid", "")).strip()
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase token does not contain a UID.",
        )
    email = str(decoded_token.get("email", "")).strip().lower() or None
    email_verified = bool(decoded_token.get("email_verified", False))
    firebase_claims = decoded_token.get("firebase") or {}
    sign_in_provider = str(
        firebase_claims.get("sign_in_provider", "")
    ).strip() or None
    return AuthenticatedUser(
        uid=uid,
        email=email,
        email_verified=email_verified,
        sign_in_provider=sign_in_provider,
    )


def authenticated_uid(user: AuthenticatedUser = Depends(authenticated_user)) -> str:
    return user.uid
