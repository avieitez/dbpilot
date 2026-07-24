from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from typing import Any

from app.core.firebase_auth import AuthenticatedUser, authenticated_user
from app.schemas.connections import (
    ConnectionTestRequest,
    DbObjectListResponse,
    DbObjectStructureResponse,
    DbObjectPreviewResponse,
    DbObjectDefinitionResponse,
    DbObjectParametersResponse,
    ObjectStructureRequest,
    ObjectPreviewRequest,
    ObjectDefinitionRequest,
    ObjectParametersRequest,
)
from app.services.db_explorer_service import DbExplorerError, DbExplorerService
from app.services.google_play_subscription_service import (
    GooglePlaySubscriptionService,
    SubscriptionVerificationError,
)

router = APIRouter(prefix="/api/v1", tags=["db_explorer"])
service = DbExplorerService()
subscription_service = GooglePlaySubscriptionService()

class QueryExecuteRequest(BaseModel):
    connection: ConnectionTestRequest
    sql: str
    limit: int = Field(default=100, ge=1, le=5000)
    allowDataModification: bool = False
    timeoutSeconds: int = Field(default=30, ge=1, le=600)

class QueryExecuteResponse(BaseModel):
    columns: list[str]
    rows: list[list[Any]]
    rowCount: int
    message: str

@router.post("/objects", response_model=DbObjectListResponse)
def get_objects(
    payload: ConnectionTestRequest,
    user: AuthenticatedUser = Depends(authenticated_user),
):
    _ = user
    try:
        return service.get_objects(payload)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/object-structure", response_model=DbObjectStructureResponse)
def get_object_structure(
    payload: ObjectStructureRequest,
    user: AuthenticatedUser = Depends(authenticated_user),
):
    _ = user
    try:
        return service.get_object_structure(payload.connection, payload.objectName, payload.objectType, payload.schemaName)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/object-preview", response_model=DbObjectPreviewResponse)
def get_object_preview(
    payload: ObjectPreviewRequest,
    user: AuthenticatedUser = Depends(authenticated_user),
):
    _ = user
    try:
        return service.get_object_preview(payload.connection, payload.objectName, payload.objectType, payload.limit, payload.schemaName)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/object-definition", response_model=DbObjectDefinitionResponse)
def get_object_definition(
    payload: ObjectDefinitionRequest,
    user: AuthenticatedUser = Depends(authenticated_user),
):
    _ = user
    try:
        return service.get_object_definition(payload.connection, payload.objectName, payload.objectType, payload.schemaName)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/object-parameters", response_model=DbObjectParametersResponse)
def get_object_parameters(
    payload: ObjectParametersRequest,
    user: AuthenticatedUser = Depends(authenticated_user),
):
    _ = user
    try:
        return service.get_object_parameters(payload.connection, payload.objectName, payload.objectType, payload.schemaName)
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.post("/execute-query", response_model=QueryExecuteResponse)
def execute_query(
    payload: QueryExecuteRequest,
    user: AuthenticatedUser = Depends(authenticated_user),
):
    try:
        if _is_data_modification_sql(payload.sql) and not _is_pro_user(user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="DBPilot Pro is required to run data modification statements.",
            )
        columns, rows = service.execute_query(
            payload.connection,
            payload.sql,
            payload.limit,
            payload.allowDataModification,
            payload.timeoutSeconds,
        )
        return QueryExecuteResponse(columns=columns, rows=rows, rowCount=len(rows), message=f"{len(rows)} rows")
    except TimeoutError as exc:
        raise HTTPException(status_code=408, detail=str(exc)) from exc
    except DbExplorerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _is_pro_user(user: AuthenticatedUser) -> bool:
    try:
        entitlement = subscription_service.status_for_user(
            user.uid,
            email=user.email,
            email_verified=user.email_verified,
            sign_in_provider=user.sign_in_provider,
        )
    except SubscriptionVerificationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Subscription status could not be verified.",
        ) from exc
    return entitlement.active


def _is_data_modification_sql(sql: str) -> bool:
    first_word = _first_sql_word(sql)
    return first_word in {
        "insert",
        "update",
        "delete",
        "merge",
        "create",
        "alter",
        "drop",
        "truncate",
        "exec",
        "execute",
        "call",
    }


def _first_sql_word(sql: str) -> str:
    clean = (sql or "").lstrip()
    while clean.startswith("--"):
        line_end = clean.find("\n")
        if line_end < 0:
            return ""
        clean = clean[line_end + 1 :].lstrip()
    return clean.split(maxsplit=1)[0].lower() if clean else ""
