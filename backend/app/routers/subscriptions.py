from fastapi import APIRouter, Depends, HTTPException, status

from app.core.firebase_auth import AuthenticatedUser, authenticated_uid, authenticated_user
from app.schemas.subscriptions import (
    GooglePlayVerificationRequest,
    SubscriptionStatusResponse,
)
from app.services.google_play_subscription_service import (
    GooglePlaySubscriptionService,
    PurchaseTokenAlreadyClaimedError,
    SubscriptionVerificationError,
)


router = APIRouter(prefix="/api/v1/subscriptions", tags=["subscriptions"])
service = GooglePlaySubscriptionService()


def _response(entitlement) -> SubscriptionStatusResponse:
    return SubscriptionStatusResponse(
        plan=entitlement.plan,
        active=entitlement.active,
        state=entitlement.state,
        productId=entitlement.product_id,
        expiryTime=entitlement.expiry_time,
    )


@router.get("/me", response_model=SubscriptionStatusResponse)
def subscription_status(user: AuthenticatedUser = Depends(authenticated_user)):
    try:
        return _response(
            service.status_for_user(
                user.uid,
                email=user.email,
                email_verified=user.email_verified,
                sign_in_provider=user.sign_in_provider,
            )
        )
    except SubscriptionVerificationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.post(
    "/google-play/verify",
    response_model=SubscriptionStatusResponse,
)
def verify_google_play_purchase(
    payload: GooglePlayVerificationRequest,
    uid: str = Depends(authenticated_uid),
):
    try:
        return _response(
            service.verify_and_assign(
                uid=uid,
                product_id=payload.product_id,
                purchase_token=payload.purchase_token,
            )
        )
    except PurchaseTokenAlreadyClaimedError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except SubscriptionVerificationError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
