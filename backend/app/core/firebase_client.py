import json
import os
from functools import lru_cache

import firebase_admin
from firebase_admin import credentials, firestore


def _service_account_info(env_name: str) -> dict | None:
    raw_value = os.getenv(env_name, "").strip()
    if not raw_value:
        return None
    return json.loads(raw_value)


@lru_cache(maxsize=1)
def get_firebase_app() -> firebase_admin.App:
    if firebase_admin._apps:
        return firebase_admin.get_app()

    account_info = _service_account_info("FIREBASE_SERVICE_ACCOUNT_JSON")
    credential = (
        credentials.Certificate(account_info)
        if account_info is not None
        else credentials.ApplicationDefault()
    )
    options = {}
    project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
    if project_id:
        options["projectId"] = project_id
    return firebase_admin.initialize_app(credential, options or None)


@lru_cache(maxsize=1)
def get_firestore_client():
    return firestore.client(app=get_firebase_app())


def get_service_account_info(env_name: str) -> dict | None:
    return _service_account_info(env_name)
