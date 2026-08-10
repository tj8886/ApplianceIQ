#!/bin/bash
# ═══════════════════════════════════════════════════════════
# ApplianceIQ Master Deploy — 100% bash, zero drag-and-drop
# Run from ~/ApplianceIQ after unzipping the master bundle there:
#   cd ~/ApplianceIQ
#   unzip -o ~/Downloads/ApplianceIQ-MASTER-DEPLOY-20260808.zip -d .
#   bash DEPLOY.sh
# ═══════════════════════════════════════════════════════════
set -e
IG_SITE_ID="9aba62a7"

echo "═══ ApplianceIQ Master Deploy ═══"

# Safety check
if [ ! -d ".git" ]; then
  echo "❌ Run this from ~/ApplianceIQ (no .git found here)"
  exit 1
fi

# 1. Remove deprecated academy directory
if [ -d "apps/academy" ]; then
  echo "→ Removing deprecated apps/academy/"
  rm -rf apps/academy
fi

# 2. Verify every fix landed before pushing
echo "→ Verifying fixes..."
FAIL=0
grep -q "api.anthropic.com" apps/up-system/index.html 2>/dev/null && { echo "❌ up-system still has direct AI call"; FAIL=1; }
grep -qE "api.anthropic.com|api.openai.com|generativelanguage" apps/pim-scraper/index.html 2>/dev/null && { echo "❌ pim-scraper still has direct AI calls"; FAIL=1; }
grep -q "loginGate" apps/pim-scraper/index.html 2>/dev/null || { echo "❌ pim-scraper missing auth gate"; FAIL=1; }
grep -q "widget.js" apps/platform/index.html 2>/dev/null || { echo "❌ platform missing AI Coach widget"; FAIL=1; }
grep -q "contact-form" apps/intelligence-group/index.html 2>/dev/null || { echo "❌ IG site missing contact form"; FAIL=1; }
grep -q "The Flywheel" apps/intelligence-group/index.html 2>/dev/null || { echo "❌ IG site missing upgraded product story"; FAIL=1; }
grep -q "toggleAuthMode" apps/iq-training/index.html 2>/dev/null || { echo "❌ academy missing signup"; FAIL=1; }
grep -q "aiqVote" apps/ai-coach/widget.js 2>/dev/null || { echo "❌ widget missing feedback buttons"; FAIL=1; }
[ "$FAIL" = "1" ] && echo "⚠️  Fixes missing — did you unzip the bundle into ~/ApplianceIQ first?" && exit 1
echo "✅ All fixes verified"

# 3. Commit and push — auto-deploys all GitHub-connected sites
git add -A
git commit -m "production launch: security hardening, marketing story, feedback loop, headers, signup, ToS/privacy" || echo "  (nothing new to commit)"
git pull --rebase origin main || true
git push origin main
echo "✅ Pushed — Netlify auto-deploys: crm, spec-iq, iq-training, up-system, iq-field, product-iq, pim-scraper, ai-coach, platform"

# 4. Intelligence Group — CLI deploy (not GitHub-connected)
echo ""
echo "→ Deploying Intelligence Group via Netlify CLI..."
if ! npx --yes netlify-cli status &>/dev/null; then
  echo "⚠️  Netlify CLI not authenticated. Run once:  npx netlify-cli login"
  echo "   (Make sure you log into YOUR main account, NOT tj@elev8talentagency.com)"
  echo "   Then re-run:  bash DEPLOY.sh"
  exit 1
fi
npx --yes netlify-cli deploy --prod --dir apps/intelligence-group --site $IG_SITE_ID
echo "✅ Intelligence Group deployed"

echo ""
echo "═══ ALL 10 SITES DEPLOYED — zero drag-and-drop ═══"
echo "Next: scripts/run-embedding-backfill.sh (after secrets are set)"
