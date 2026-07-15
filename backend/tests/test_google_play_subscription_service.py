import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from app.services.google_play_subscription_service import (
    GooglePlaySubscriptionService,
    SubscriptionVerificationError,
)


class GooglePlaySubscriptionServiceTests(unittest.TestCase):
    def setUp(self):
        self.service = GooglePlaySubscriptionService()

    def _payload(self, state: str, expiry: datetime, product_id: str | None = None):
        return {
            "subscriptionState": state,
            "lineItems": [
                {
                    "productId": product_id or self.service.product_id,
                    "expiryTime": expiry.isoformat().replace("+00:00", "Z"),
                }
            ],
        }

    def test_active_subscription_grants_pro(self):
        payload = self._payload(
            "SUBSCRIPTION_STATE_ACTIVE",
            datetime.now(timezone.utc) + timedelta(days=30),
        )

        entitlement = self.service._entitlement_from_payload(
            payload,
            self.service.product_id,
        )

        self.assertTrue(entitlement.active)
        self.assertEqual(entitlement.plan, "pro")

    def test_canceled_subscription_remains_pro_until_expiry(self):
        payload = self._payload(
            "SUBSCRIPTION_STATE_CANCELED",
            datetime.now(timezone.utc) + timedelta(days=2),
        )

        entitlement = self.service._entitlement_from_payload(
            payload,
            self.service.product_id,
        )

        self.assertTrue(entitlement.active)

    def test_yearly_subscription_grants_pro(self):
        yearly_product_id = "dbpilot_pro_yearly"
        payload = self._payload(
            "SUBSCRIPTION_STATE_ACTIVE",
            datetime.now(timezone.utc) + timedelta(days=365),
            product_id=yearly_product_id,
        )

        entitlement = self.service._entitlement_from_payload(
            payload,
            yearly_product_id,
        )

        self.assertTrue(entitlement.active)
        self.assertEqual(entitlement.product_id, yearly_product_id)

    def test_expired_subscription_is_free(self):
        payload = self._payload(
            "SUBSCRIPTION_STATE_EXPIRED",
            datetime.now(timezone.utc) - timedelta(seconds=1),
        )

        entitlement = self.service._entitlement_from_payload(
            payload,
            self.service.product_id,
        )

        self.assertFalse(entitlement.active)
        self.assertEqual(entitlement.plan, "free")

    def test_wrong_product_is_rejected(self):
        payload = self._payload(
            "SUBSCRIPTION_STATE_ACTIVE",
            datetime.now(timezone.utc) + timedelta(days=30),
            product_id="another_product",
        )

        with self.assertRaises(SubscriptionVerificationError):
            self.service._entitlement_from_payload(
                payload,
                self.service.product_id,
            )

    def test_review_access_grants_pro_for_allowed_uid(self):
        uid = "review-user-uid"
        self.service.review_access_uids = {uid}
        expiry = datetime.now(timezone.utc) + timedelta(days=365)

        entitlement = self.service._review_access_entitlement(
            uid,
            {
                "reviewAccess": True,
                "productId": "dbpilot_pro_yearly",
                "state": "REVIEW_ACCESS_ACTIVE",
                "expiryTime": expiry.isoformat().replace("+00:00", "Z"),
            },
        )

        self.assertIsNotNone(entitlement)
        self.assertTrue(entitlement.active)
        self.assertEqual(entitlement.plan, "pro")
        self.assertEqual(entitlement.product_id, "dbpilot_pro_yearly")

    def test_review_access_is_ignored_for_unlisted_uid(self):
        self.service.review_access_uids = {"review-user-uid"}
        expiry = datetime.now(timezone.utc) + timedelta(days=365)

        entitlement = self.service._review_access_entitlement(
            "different-user-uid",
            {
                "reviewAccess": True,
                "productId": "dbpilot_pro_yearly",
                "expiryTime": expiry.isoformat().replace("+00:00", "Z"),
            },
        )

        self.assertIsNone(entitlement)

    def test_review_access_uids_are_loaded_from_environment(self):
        with patch.dict(
            "os.environ",
            {"GOOGLE_PLAY_REVIEW_ACCESS_UIDS": "uid-a, uid-b"},
        ):
            service = GooglePlaySubscriptionService()

        self.assertEqual(service.review_access_uids, {"uid-a", "uid-b"})

    def test_review_access_email_grants_pro_when_verified(self):
        entitlement = self.service._email_review_access_entitlement(
            uid="review-uid",
            email="dbpilot.review@gmail.com",
            email_verified=True,
        )

        self.assertIsNotNone(entitlement)
        self.assertTrue(entitlement.active)
        self.assertEqual(entitlement.plan, "pro")
        self.assertEqual(entitlement.product_id, "dbpilot_pro_yearly")

    def test_review_access_email_is_ignored_when_unverified(self):
        entitlement = self.service._email_review_access_entitlement(
            uid="review-uid",
            email="dbpilot.review@gmail.com",
            email_verified=False,
        )

        self.assertIsNone(entitlement)

    def test_review_access_emails_are_loaded_from_environment(self):
        with patch.dict(
            "os.environ",
            {"GOOGLE_PLAY_REVIEW_ACCESS_EMAILS": "review@example.com"},
        ):
            service = GooglePlaySubscriptionService()

        self.assertEqual(service.review_access_emails, {"review@example.com"})


if __name__ == "__main__":
    unittest.main()
