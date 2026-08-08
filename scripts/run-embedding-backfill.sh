#!/bin/bash
# Embeds all 8,400+ knowledge chunks for semantic search
# Requires: GOOGLE_API_KEY set in Supabase secrets, and a valid user session token
# Usage: SUPABASE_TOKEN=your_access_token bash run-embedding-backfill.sh

URL="https://fumwwhyozeouoqscolke.supabase.co/functions/v1/embed-knowledge"
ANON="sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV"

if [ -z "$SUPABASE_TOKEN" ]; then
  echo "Set SUPABASE_TOKEN first. Get it from any logged-in app:"
  echo "  JSON.parse(localStorage.getItem('sb-fumwwhyozeouoqscolke-auth-token')).access_token"
  exit 1
fi

echo "Starting embedding backfill (batches of 100)..."
for i in $(seq 1 100); do
  RESULT=$(curl -s -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $SUPABASE_TOKEN" \
    -H "apikey: $ANON" \
    -d '{"batch_size": 100}')
  echo "Batch $i: $RESULT"
  REMAINING=$(echo "$RESULT" | grep -oE '"remaining":[0-9]+' | grep -oE '[0-9]+')
  if [ "$REMAINING" = "0" ] || [ -z "$REMAINING" ]; then
    echo "✅ All chunks embedded!"
    break
  fi
  sleep 2
done
