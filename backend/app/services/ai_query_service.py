import json
import os
import urllib.error
import urllib.request


class AiQueryError(Exception):
    pass


def _extract_response_text(data: dict) -> str:
    direct = data.get("output_text")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()

    parts: list[str] = []
    for item in data.get("output", []) or []:
        for content in item.get("content", []) or []:
            text = content.get("text")
            if isinstance(text, str):
                parts.append(text)
    return "\n".join(parts).strip()


def _clean_sql(value: str) -> str:
    clean = value.strip()
    if clean.startswith("```"):
        clean = clean.strip("`").strip()
        if clean.lower().startswith("sql"):
            clean = clean[3:].strip()
    return clean.strip()


def generate_sql_with_ai(
    *,
    provider: str,
    request_text: str,
    current_sql: str | None = None,
    object_name: str | None = None,
    object_type: str | None = None,
    schema_name: str | None = None,
) -> dict:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise AiQueryError("OPENAI_API_KEY is not configured on the backend.")

    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    context = {
        "provider": provider,
        "objectName": object_name,
        "objectType": object_type,
        "schemaName": schema_name,
        "currentSql": current_sql,
        "userRequest": request_text,
    }

    body = {
        "model": model,
        "instructions": (
            "You generate SQL for a mobile database query editor. "
            "Return only valid JSON with keys sql and notes. "
            "The sql value must contain only SQL, no markdown fences. "
            "Generate dialect-specific SQL for the provider. "
            "Do not invent credentials. Prefer read-only SELECT queries unless the user explicitly asks for DDL or DML."
        ),
        "input": (
            "Generate a SQL query for this request and context:\n"
            f"{json.dumps(context, ensure_ascii=False)}"
        ),
        "text": {
            "format": {
                "type": "json_schema",
                "name": "sql_generation",
                "schema": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "sql": {"type": "string"},
                        "notes": {"type": "string"},
                    },
                    "required": ["sql", "notes"],
                },
                "strict": True,
            }
        },
    }

    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise AiQueryError(f"OpenAI request failed: {detail}") from exc
    except Exception as exc:
        raise AiQueryError(f"OpenAI request failed: {exc}") from exc

    text = _extract_response_text(data)
    if not text:
        raise AiQueryError("OpenAI returned an empty response.")

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise AiQueryError("OpenAI returned an invalid SQL response.") from exc

    sql = _clean_sql(str(parsed.get("sql") or ""))
    if not sql:
        raise AiQueryError("OpenAI did not generate SQL.")

    return {
        "sql": sql,
        "notes": str(parsed.get("notes") or ""),
    }
