from fastapi import FastAPI
from app.routers.connections import router as connections_router

app = FastAPI(title="DBPilot API", version="0.1.0")
app.include_router(connections_router)


@app.get("/health")
def health():
    return {"status": "ok"}
