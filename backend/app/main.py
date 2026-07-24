import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.account import router as account_router
from app.routers.connections import router as connections_router
from app.routers.db_explorer import router as db_explorer_router
from app.routers.subscriptions import router as subscriptions_router

app = FastAPI(
    title="DBPilot API",
    version="1.1.0"
)

cors_allowed_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]

if cors_allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_allowed_origins,
        allow_credentials=False,
        allow_methods=["POST", "GET", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )

@app.get("/health")
def health():
    return {"status": "ok"}

app.include_router(connections_router)
app.include_router(db_explorer_router)
app.include_router(subscriptions_router)
app.include_router(account_router)

@app.get("/")
def root():
    return {"message": "DBPilot FASTAPI OK V4"}
