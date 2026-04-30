from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Any

from app.schemas.connections import (
    ConnectionTestRequest,
    DbObjectListResponse,
    DbObjectStructureResponse,
    DbObjectPreviewResponse,
    ObjectStructureRequest,
    ObjectPreviewRequest,
)
from app.services.db_explorer_service import DbExplorerError, DbExplorerService

router = APIRouter(prefix="/api/v1", tags=["db_explorer"])
service = DbExplorerService()


class QueryExecuteRequest(BaseModel):
    connection: ConnectionTestRequest
    sql: str
    limit: int = 100
    allowDataModification: bool = False


class QueryExecuteResponse(BaseModel):
    columns: list[str]
    rows: list[list[Any]]
    rowCount: int
    message: str


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


@router.post("/execute-query", response_model=QueryExecuteResponse)
def execute_query(payload: QueryExecuteRequest):
    try:
        columns, rows = service.execute_query(
            payload.connection,
            payload.sql,
            payload.limit,
            payload.allowDataModification,
        )
        return QueryExecuteResponse(
            columns=columns,
            rows=rows,
            rowCount=len(rows),
            message=f"{len(rows)} filas",
        )
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
