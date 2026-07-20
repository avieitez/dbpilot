import hashlib
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from urllib.parse import quote

import google.auth
from google.api_core.exceptions import AlreadyExists, PermissionDenied
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

from app.core.firebase_client import (
    get_firestore_client,
    get_service_account_info,
)


ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
DEFAULT_PACKAGE_NAME = "com.avieitez.dbpilot"
DEFAULT_PRODUCT_ID = "dbpilot_pro_monthly"
DEFAULT_PRODUCT_IDS = ("dbpilot_pro_monthly", "dbpilot_pro_yearly")
DEFAULT_REVIEW_ACCESS_EMAILS = ("dbpilot.review@gmail.com",)
ENTITLED_STATES = {
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
}


class SubscriptionVerificationError(Exception):
    pass


class PurchaseTokenAlreadyClaimedError(SubscriptionVerificationError):
    pass


@dataclass(frozen=True)
class SubscriptionEntitlement:
    active: bool
    state: str | None
    product_id: str | None
    expiry_time: str | None

    @property
    def plan(self) -> str:
        return "pro" if self.active else "free"


@lru_cache(maxsize=1)
def _authorized_session() -> AuthorizedSession:
    account_info = get_service_account_info("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if account_info is None:
        account_info = get_service_account_info("FIREBASE_SERVICE_ACCOUNT_JSON")

    if account_info is not None:
        credentials = service_account.Credentials.from_service_account_info(
            account_info,
            scopes=[ANDROID_PUBLISHER_SCOPE],
        )
    else:
        credentials, _ = google.auth.default(scopes=[ANDROID_PUBLISHER_SCOPE])
    return AuthorizedSession(credentials)


class GooglePlaySubscriptionService:
    def __init__(self):
        self.package_name = os.getenv(
            "GOOGLE_PLAY_PACKAGE_NAME", DEFAULT_PACKAGE_NAME
        ).strip()
        self.product_ids = self._configured_product_ids()
        self.product_id = self.product_ids[0]
        self.review_access_uids = self._configured_review_access_uids()
        self.review_access_emails = self._configured_review_access_emails()

    def verify_and_assign(
        self,
        *,
        uid: str,
        product_id: str,
        purchase_token: str,
    ) -> SubscriptionEntitlement:
        if product_id not in self.product_ids:
            configured = ", ".join(self.product_ids)
            raise SubscriptionVerificationError(
                f"Unknown subscription product '{product_id}'. Configured products: {configured}."
            )

        payload = self._get_subscription(purchase_token)
        entitlement = self._entitlement_from_payload(payload, product_id)
        self._validate_account_identifier(payload, uid)

        if entitlement.active:
            self._assign_token(uid, purchase_token, payload, entitlement)
        return entitlement

    def status_for_user(
        self,
        uid: str,
        *,
        email: str | None = None,
        email_verified: bool = False,
        sign_in_provider: str | None = None,
    ) -> SubscriptionEntitlement:
        email_review_entitlement = self._email_review_access_entitlement(
            uid=uid,
            email=email,
            email_verified=email_verified,
            sign_in_provider=sign_in_provider,
        )
        if email_review_entitlement is not None:
            self._store_review_access(uid, email_review_entitlement)
            return email_review_entitlement

        firestore_client = get_firestore_client()
        subscription_ref = (
            firestore_client.collection("users")
            .document(uid)
            .collection("subscriptions")
            .document("google_play")
        )
        try:
            snapshot = subscription_ref.get()
        except PermissionDenied as exc:
            raise SubscriptionVerificationError(
                "Firestore permission denied. Check FIREBASE_SERVICE_ACCOUNT_JSON permissions."
            ) from exc

        if not snapshot.exists:
            return SubscriptionEntitlement(False, None, None, None)

        stored = snapshot.to_dict() or {}
        review_entitlement = self._review_access_entitlement(uid, stored)
        if review_entitlement is not None:
            return review_entitlement

        purchase_token = str(stored.get("purchaseToken", "")).strip()
        product_id = str(stored.get("productId", self.product_id)).strip()
        if not purchase_token or product_id not in self.product_ids:
            return SubscriptionEntitlement(False, None, product_id or None, None)

        try:
            payload = self._get_subscription(purchase_token)
            entitlement = self._entitlement_from_payload(payload, product_id)
        except SubscriptionVerificationError:
            return SubscriptionEntitlement(False, None, product_id, None)

        try:
            subscription_ref.set(
                self._subscription_record(purchase_token, payload, entitlement),
                merge=True,
            )
        except PermissionDenied as exc:
            raise SubscriptionVerificationError(
                "Firestore permission denied. Check FIREBASE_SERVICE_ACCOUNT_JSON permissions."
            ) from exc
        return entitlement

    def _get_subscription(self, purchase_token: str) -> dict:
        encoded_package = quote(self.package_name, safe="")
        encoded_token = quote(purchase_token, safe="")
        url = (
            "https://androidpublisher.googleapis.com/androidpublisher/v3/"
            f"applications/{encoded_package}/purchases/subscriptionsv2/"
            f"tokens/{encoded_token}"
        )
        try:
            response = _authorized_session().get(url, timeout=15)
        except Exception as exc:
            raise SubscriptionVerificationError(
                "Google Play verification is temporarily unavailable."
            ) from exc

        if response.status_code != 200:
            response_detail = response.text[:500].replace("\n", " ").strip()
            raise SubscriptionVerificationError(
                "Google Play rejected the purchase token "
                f"({response.status_code}). Detail: {response_detail}"
            )
        return response.json()

    def _entitlement_from_payload(
        self,
        payload: dict,
        expected_product_id: str,
    ) -> SubscriptionEntitlement:
        line_items = payload.get("lineItems") or []
        matching_items = [
            item for item in line_items if item.get("productId") == expected_product_id
        ]
        entitlement_product_id = expected_product_id

        if not matching_items:
            matching_items = [
                item
                for item in line_items
                if str(item.get("productId", "")).strip() in self.product_ids
            ]
            if matching_items:
                entitlement_product_id = str(
                    matching_items[0].get("productId", "")
                ).strip()

        if not matching_items:
            token_products = [
                str(item.get("productId", "")).strip()
                for item in line_items
                if str(item.get("productId", "")).strip()
            ]
            configured = ", ".join(self.product_ids)
            raise SubscriptionVerificationError(
                "Purchase token does not contain a configured PRO product. "
                f"Expected '{expected_product_id}' or one of [{configured}]. "
                f"Token products: {token_products}."
            )

        expiry_time = max(
            (str(item.get("expiryTime", "")) for item in matching_items),
            default="",
        )
        expiry = self._parse_timestamp(expiry_time)
        state = str(payload.get("subscriptionState", "")) or None
        active = (
            state in ENTITLED_STATES
            and expiry is not None
            and expiry > datetime.now(timezone.utc)
        )
        return SubscriptionEntitlement(
            active=active,
            state=state,
            product_id=entitlement_product_id,
            expiry_time=expiry_time or None,
        )

    def _validate_account_identifier(self, payload: dict, uid: str) -> None:
        identifiers = payload.get("externalAccountIdentifiers") or {}
        account_id = str(
            identifiers.get("obfuscatedExternalAccountId", "")
        ).strip()
        if account_id and account_id != uid:
            raise SubscriptionVerificationError(
                "Purchase belongs to a different DBPilot account."
            )

    def _assign_token(
        self,
        uid: str,
        purchase_token: str,
        payload: dict,
        entitlement: SubscriptionEntitlement,
    ) -> None:
        firestore_client = get_firestore_client()
        token_hash = self._token_hash(purchase_token)
        token_ref = firestore_client.collection("play_purchase_tokens").document(
            token_hash
        )
        try:
            token_ref.create({"uid": uid, "productId": entitlement.product_id})
        except AlreadyExists:
            token_snapshot = token_ref.get()
            owner_uid = str((token_snapshot.to_dict() or {}).get("uid", ""))
            if owner_uid and owner_uid != uid:
                raise PurchaseTokenAlreadyClaimedError(
                    "Purchase is already linked to another DBPilot account."
                )
        except PermissionDenied as exc:
            raise SubscriptionVerificationError(
                "Firestore permission denied. Check FIREBASE_SERVICE_ACCOUNT_JSON permissions."
            ) from exc

        subscription_ref = (
            firestore_client.collection("users")
            .document(uid)
            .collection("subscriptions")
            .document("google_play")
        )
        try:
            subscription_ref.set(
                self._subscription_record(purchase_token, payload, entitlement)
            )
        except PermissionDenied as exc:
            raise SubscriptionVerificationError(
                "Firestore permission denied. Check FIREBASE_SERVICE_ACCOUNT_JSON permissions."
            ) from exc

        linked_token = str(payload.get("linkedPurchaseToken", "")).strip()
        if linked_token:
            linked_ref = firestore_client.collection(
                "play_purchase_tokens"
            ).document(self._token_hash(linked_token))
            linked_ref.delete()

    def _subscription_record(
        self,
        purchase_token: str,
        payload: dict,
        entitlement: SubscriptionEntitlement,
    ) -> dict:
        return {
            "purchaseToken": purchase_token,
            "purchaseTokenHash": self._token_hash(purchase_token),
            "productId": entitlement.product_id,
            "state": entitlement.state,
            "expiryTime": entitlement.expiry_time,
            "active": entitlement.active,
            "latestOrderId": payload.get("latestOrderId"),
            "updatedAt": datetime.now(timezone.utc).isoformat(),
        }

    def _review_access_entitlement(
        self,
        uid: str,
        stored: dict,
    ) -> SubscriptionEntitlement | None:
        if uid not in self.review_access_uids:
            return None
        if stored.get("reviewAccess") is not True:
            return None

        product_id = str(stored.get("productId", self.product_id)).strip()
        if product_id not in self.product_ids:
            return None

        expiry_time = str(stored.get("expiryTime", "")).strip()
        expiry = self._parse_timestamp(expiry_time)
        if expiry is None or expiry <= datetime.now(timezone.utc):
            return SubscriptionEntitlement(
                False,
                "REVIEW_ACCESS_EXPIRED",
                product_id,
                expiry_time or None,
            )

        state = str(stored.get("state", "REVIEW_ACCESS_ACTIVE")).strip()
        return SubscriptionEntitlement(
            active=True,
            state=state or "REVIEW_ACCESS_ACTIVE",
            product_id=product_id,
            expiry_time=expiry_time,
        )

    def _email_review_access_entitlement(
        self,
        *,
        uid: str,
        email: str | None,
        email_verified: bool,
        sign_in_provider: str | None = None,
    ) -> SubscriptionEntitlement | None:
        normalized_email = (email or "").strip().lower()
        is_google_account = (sign_in_provider or "").strip() == "google.com"
        if not uid.strip() or not (email_verified or is_google_account):
            return None
        if normalized_email not in self.review_access_emails:
            return None

        return SubscriptionEntitlement(
            active=True,
            state="REVIEW_ACCESS_ACTIVE",
            product_id="dbpilot_pro_yearly",
            expiry_time="2099-12-31T23:59:59Z",
        )

    def _store_review_access(
        self,
        uid: str,
        entitlement: SubscriptionEntitlement,
    ) -> None:
        try:
            firestore_client = get_firestore_client()
            subscription_ref = (
                firestore_client.collection("users")
                .document(uid)
                .collection("subscriptions")
                .document("google_play")
            )
            subscription_ref.set(
                self._review_access_record(entitlement),
                merge=True,
            )
        except Exception:
            # Review access must not fail open for normal users because the
            # entitlement is already restricted by verified Google identity.
            pass

    @staticmethod
    def _review_access_record(entitlement: SubscriptionEntitlement) -> dict:
        return {
            "reviewAccess": True,
            "productId": entitlement.product_id,
            "state": entitlement.state,
            "active": entitlement.active,
            "expiryTime": entitlement.expiry_time,
            "latestOrderId": "review-access",
            "updatedAt": datetime.now(timezone.utc).isoformat(),
            "source": "google_play_review_email",
        }

    @staticmethod
    def _token_hash(purchase_token: str) -> str:
        return hashlib.sha256(purchase_token.encode("utf-8")).hexdigest()

    @staticmethod
    def _configured_product_ids() -> tuple[str, ...]:
        product_ids: list[str] = []

        raw_ids = os.getenv("GOOGLE_PLAY_PRO_PRODUCT_IDS", "").strip()
        if raw_ids:
            product_ids.extend(
                product_id.strip()
                for product_id in raw_ids.split(",")
                if product_id.strip()
            )

        legacy_product_id = os.getenv("GOOGLE_PLAY_PRO_PRODUCT_ID", "").strip()
        if legacy_product_id:
            product_ids.append(legacy_product_id)

        product_ids.extend(DEFAULT_PRODUCT_IDS)
        return tuple(dict.fromkeys(product_ids))

    @staticmethod
    def _configured_review_access_uids() -> set[str]:
        raw_uids = os.getenv("GOOGLE_PLAY_REVIEW_ACCESS_UIDS", "").strip()
        if not raw_uids:
            return set()
        return {uid.strip() for uid in raw_uids.split(",") if uid.strip()}

    @staticmethod
    def _configured_review_access_emails() -> set[str]:
        raw_emails = os.getenv("GOOGLE_PLAY_REVIEW_ACCESS_EMAILS", "").strip()
        if not raw_emails:
            return set(DEFAULT_REVIEW_ACCESS_EMAILS)
        return {
            email.strip().lower()
            for email in raw_emails.split(",")
            if email.strip()
        }

    @staticmethod
    def _parse_timestamp(value: str) -> datetime | None:
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
