export function normalizeTurnstileRequest(payload = {}) {
  const token = typeof payload.token === "string" ? payload.token.trim() : "";
  const action = typeof payload.action === "string" && payload.action.trim().length > 0 ? payload.action.trim() : null;
  const cdata = typeof payload.cdata === "string" && payload.cdata.trim().length > 0 ? payload.cdata.trim() : null;
  const idempotencyKey = typeof payload.idempotency_key === "string" && payload.idempotency_key.trim().length > 0 ? payload.idempotency_key.trim() : null;
  return { token, action, cdata, idempotencyKey };
}

export function buildTurnstileFailure(code, message, status = 400) {
  return { ok: false, code, message, status };
}
