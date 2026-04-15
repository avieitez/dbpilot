from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.connections import router as connections_router

app = FastAPI(
    title="DBPilot API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok"}

app.include_router(connections_router)

@app.get("/")
def root():
    return {"message": "DBPilot FASTAPI OK V3"}