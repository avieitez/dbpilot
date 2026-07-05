import unittest
from datetime import datetime, timedelta, timezone

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


if __name__ == "__main__":
    unittest.main()
