from fastapi import APIRouter, HTTPException

from app.schemas.connections import ConnectionTestRequest, ConnectionTestResponse
from app.services.db_tester import ConnectionTestError, DbTesterService

router = APIRouter(prefix="/api/v1", tags=["connections"])
service = DbTesterService()

@router.get("/health")
def health_check():
    return {"status": "ok"}

@router.get("/test-connection")
def test_connection_info():
    return {"message": "Use POST to test a connection."}

@router.post("/test-connection", response_model=ConnectionTestResponse)
def test_connection(payload: ConnectionTestRequest):
    try:
        return service.test_connection(payload)
    except ConnectionTestError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
