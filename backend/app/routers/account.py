from fastapi import APIRouter, Depends, HTTPException, status
from firebase_admin import auth

from app.core.firebase_auth import authenticated_uid
from app.core.firebase_client import get_firebase_app, get_firestore_client


router = APIRouter(prefix="/api/v1/account", tags=["account"])


@router.delete("")
def delete_account(uid: str = Depends(authenticated_uid)):
    try:
        _delete_user_firestore_data(uid)
        auth.delete_user(uid, app=get_firebase_app())
    except auth.UserNotFoundError:
        return {"deleted": True}
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Account deletion failed.",
        ) from exc

    return {"deleted": True}


def _delete_user_firestore_data(uid: str) -> None:
    firestore_client = get_firestore_client()
    user_ref = firestore_client.collection("users").document(uid)

    for collection_ref in user_ref.collections():
        _delete_collection(collection_ref)
    user_ref.delete()

    token_docs = (
        firestore_client.collection("play_purchase_tokens")
        .where("uid", "==", uid)
        .stream()
    )
    for token_doc in token_docs:
        token_doc.reference.delete()


def _delete_collection(collection_ref, batch_size: int = 100) -> None:
    while True:
        docs = list(collection_ref.limit(batch_size).stream())
        if not docs:
            return

        for doc in docs:
            doc.reference.delete()
