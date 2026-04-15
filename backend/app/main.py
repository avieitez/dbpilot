from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers.connections import router as connections_router

app = FastAPI(title="DBPilot API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(connections_router)


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "DBPilot backend is running"}
