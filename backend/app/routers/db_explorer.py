from fastapi import APIRouter, HTTPException

from app.schemas.connections import (
    ConnectionTestRequest,
    DbObjectListResponse,
    DbObjectStructureResponse,
    DbObjectPreviewResponse,
    ObjectStructureRequest,
    ObjectPreviewRequest,
)
from app.services.db_explorer_service import DbExplorerError, DbExplorerService

router = APIRouter(prefix="/api/v1/db-explorer", tags=["db-explorer"])
service = DbExplorerService()

@router.post("/objects", response_model=DbObjectListResponse)
def get_objects(payload: ConnectionTestRequest):
    try:
        return service.get_objects(payload)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/object-structure", response_model=DbObjectStructureResponse)
def get_object_structure(payload: ObjectStructureRequest):
    try:
        return service.get_object_structure(payload.connection, payload.objectName, payload.objectType)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/object-preview", response_model=DbObjectPreviewResponse)
def get_object_preview(payload: ObjectPreviewRequest):
    try:
        return service.get_object_preview(
            payload.connection,
            payload.objectName,
            payload.objectType,
            payload.limit,
        )
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
