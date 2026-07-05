from pydantic import BaseModel, ConfigDict, Field


class GooglePlayVerificationRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    product_id: str = Field(alias="productId", min_length=1)
    purchase_token: str = Field(alias="purchaseToken", min_length=1)


class SubscriptionStatusResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    plan: str
    active: bool
    state: str | None = None
    product_id: str | None = Field(default=None, alias="productId")
    expiry_time: str | None = Field(default=None, alias="expiryTime")
