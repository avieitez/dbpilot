import logging

from fastapi import APIRouter, Depends, HTTPException, status
from firebase_admin import auth

from app.core.firebase_auth import authenticated_uid
from app.core.firebase_client import get_firebase_app, get_firestore_client


router = APIRouter(prefix="/api/v1/account", tags=["account"])
logger = logging.getLogger(__name__)


@router.delete("")
def delete_account(uid: str = Depends(authenticated_uid)):
    try:
        warnings = _delete_user_firestore_data(uid)
    except Exception as exc:
        logger.exception("Failed to delete Firestore account data for uid=%s", uid)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Could not delete account data.",
        ) from exc

    try:
        auth.delete_user(uid, app=get_firebase_app())
    except Exception as exc:
        if exc.__class__.__name__ == "UserNotFoundError":
            return {"deleted": True}
        logger.exception("Failed to delete Firebase Auth user uid=%s", uid)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Could not delete Firebase Authentication user.",
        ) from exc

    return {"deleted": True, "warnings": warnings}


def _delete_user_firestore_data(uid: str) -> list[str]:
    firestore_client = get_firestore_client()
    user_ref = firestore_client.collection("users").document(uid)
    warnings: list[str] = []

    for collection_ref in user_ref.collections():
        _delete_collection(collection_ref)
    user_ref.delete()

    try:
        token_docs = (
            firestore_client.collection("play_purchase_tokens")
            .where("uid", "==", uid)
            .stream()
        )
        for token_doc in token_docs:
            token_doc.reference.delete()
    except Exception:
        logger.exception("Failed to delete purchase token references for uid=%s", uid)
        warnings.append("Purchase token references could not be fully removed.")

    return warnings


def _delete_collection(collection_ref, batch_size: int = 100) -> None:
    while True:
        docs = list(collection_ref.limit(batch_size).stream())
        if not docs:
            return

        for doc in docs:
            doc.reference.delete()
