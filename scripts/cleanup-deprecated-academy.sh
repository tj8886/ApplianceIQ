#!/bin/bash
# Run from ~/ApplianceIQ
# Removes the deprecated apps/academy/ directory from the repo
# The LIVE academy is at apps/iq-training/ (iqacademy-appliance-training.netlify.app)

echo "=== Removing deprecated apps/academy/ ==="
if [ -d "apps/academy" ]; then
  rm -rf apps/academy
  git add -A
  git commit -m "cleanup: remove deprecated apps/academy directory (live academy is apps/iq-training)"
  git push origin main
  echo "✅ Done — apps/academy removed"
else
  echo "apps/academy/ not found — already removed or wrong directory"
fi
