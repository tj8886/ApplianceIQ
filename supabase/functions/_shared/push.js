export function buildPushPayload({ title, body, url, tag, notificationId, organizationId, appKey }) {
  return { title, body, url, tag, notification_id: notificationId ?? null, organization_id: organizationId ?? null, app_key: appKey ?? "universal" };
}

export function isExpiredPushSubscription(subscription) {
  if (!subscription) return false;
  const status = String(subscription.status ?? "").toLowerCase();
  if (["expired","revoked","disconnected"].includes(status)) return true;
  const lastSeenAt = subscription.last_seen_at ?? subscription.revoked_at ?? subscription.token_expires_at ?? null;
  if (!lastSeenAt) return false;
  const timestamp = new Date(lastSeenAt);
  if (Number.isNaN(timestamp.getTime())) return false;
  return timestamp.getTime() < Date.now() - 1000;
}
