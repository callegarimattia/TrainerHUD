#!/bin/bash
# Build, copy to /Applications, and relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh release
pkill -x TrainerHUD 2>/dev/null || true
sleep 1
rm -rf /Applications/TrainerHUD.app
cp -R build/TrainerHUD.app /Applications/TrainerHUD.app
open /Applications/TrainerHUD.app
echo "Installed and launched /Applications/TrainerHUD.app"
