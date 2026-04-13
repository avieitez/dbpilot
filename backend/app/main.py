from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .schemas import ConnectionTestRequest, ConnectionTestResponse
from .services.db_tester import ConnectionTestError, DbTesterService

app = FastAPI(title="DBPilot API", version="0.1.0")
service = DbTesterService()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/v1/test-connection", response_model=ConnectionTestResponse)
def test_connection(payload: ConnectionTestRequest) -> ConnectionTestResponse:
    try:
        return service.test_connection(payload)
    except ConnectionTestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
