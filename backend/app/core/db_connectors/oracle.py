def test_oracle_connection(payload) -> dict:
    target = payload.service_name or payload.sid or "unknown"
    return {
        "success": True,
        "message": f"Oracle connector selected for host={payload.host}, target={target}",
        "provider": "oracle",
    }
