const DEFAULT_CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-request-id, idempotency-key",
  "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
  "access-control-max-age": "86400"
};

export function mergeHeaders(...headerSets) {
  return Object.assign({}, DEFAULT_CORS_HEADERS, ...headerSets);
}

export function jsonResponse(body, init = {}) {
  const headers = mergeHeaders(init.headers ?? {}, {
    "content-type": "application/json; charset=utf-8"
  });
  return new Response(JSON.stringify(body), { ...init, headers });
}

export function errorResponse(status, message, details = null) {
  return jsonResponse({ error: { message, details } }, { status });
}

export async function parseJsonRequest(request) {
  const rawBody = await request.text();
  if (!rawBody.trim()) return null;
  try { return JSON.parse(rawBody); } catch { throw new Error("Malformed JSON body"); }
}

export function ensureAllowedMethod(request, allowedMethods) {
  const method = request.method.toUpperCase();
  if (!allowedMethods.map((v) => v.toUpperCase()).includes(method)) {
    throw new Error(`Method not allowed: ${method}`);
  }
}

export function withCors(response, headers = {}) {
  const mergedHeaders = mergeHeaders(Object.fromEntries(response.headers.entries()), headers);
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers: mergedHeaders });
}

export function createHttpError(status, message, details = null) {
  const error = new Error(message);
  error.status = status;
  error.details = details;
  return error;
}

export function normalizeHttpError(error) {
  if (error instanceof Error) {
    return { message: error.message, status: typeof error.status === "number" ? error.status : 500, details: error.details ?? null };
  }
  return { message: String(error), status: 500, details: null };
}
