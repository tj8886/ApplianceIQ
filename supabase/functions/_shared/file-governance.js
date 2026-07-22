const SAFE_MIME_TYPES = new Set([
  "application/pdf", "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "text/plain", "text/csv", "application/rtf",
  "image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml"
]);

const BLOCKED_EXTENSIONS = new Set([
  "exe","msi","bat","cmd","sh","ps1","app","apk","dmg","pkg","deb","rpm","js","jar","vbs","scr"
]);

export function normalizeSignedUrlPurpose(value) {
  const purpose = String(value ?? "").trim().toLowerCase();
  if (["download","preview","share","attachment"].includes(purpose)) return purpose;
  return "download";
}

export function classifyFileScan({ fileName = "", mimeType = null, sizeBytes = null, headHex = "" } = {}) {
  const extension = String(fileName).toLowerCase().split(".").pop() || "";
  if (BLOCKED_EXTENSIONS.has(extension)) return { status: "unsupported", reason: "blocked_extension", details: { extension } };
  if (mimeType && !SAFE_MIME_TYPES.has(mimeType)) return { status: "unsupported", reason: "disallowed_mime_type", details: { mime_type: mimeType } };
  if ((sizeBytes ?? 0) > 100 * 1024 * 1024) return { status: "failed", reason: "oversize", details: { size_bytes: sizeBytes } };
  if (headHex.startsWith("4d5a")) return { status: "infected", reason: "pe_executable_signature", details: { head_hex: headHex } };
  if (headHex.startsWith("7f454c46")) return { status: "infected", reason: "elf_executable_signature", details: { head_hex: headHex } };
  return { status: "clean", reason: "static_rules_v1", details: { head_hex: headHex } };
}

export function normalizeStorageDeletionStatus(value) {
  const status = String(value ?? "").trim().toLowerCase();
  if (["queued","deleting","deleted","failed","cancelled"].includes(status)) return status;
  return "queued";
}

export function isRetryableDeletionFailure(errorMessage) {
  if (!errorMessage) return true;
  const normalized = String(errorMessage).toLowerCase();
  return !normalized.includes("not found") && !normalized.includes("404");
}
