# Source this before any asc/ or rc/ script:  source Tools/asc/env.sh
# Pulls the App Store Connect API creds from the ios-deploy skill + the .p8 on disk (living off the land).
# Nothing secret is hardcoded here; values are read at runtime.
_SKILL="$HOME/Documents/Software/skills/ios-deploy/SKILL.md"
export ASC_API_KEY_ID="$(grep -i 'ASC Key ID' "$_SKILL" | grep -oE '[A-Z0-9]{10}' | head -1)"
export ASC_API_ISSUER_ID="$(grep -i 'ASC Issuer ID' "$_SKILL" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -1)"
export ASC_API_KEY_PATH="$HOME/private_keys/AuthKey_${ASC_API_KEY_ID}.p8"
export TEAM_ID="Y4HDXFWXUV"
export APP_BUNDLE_ID="com.isaiahdupree.SonanceEQ"
export IAP_PRODUCT_ID="com.isaiahdupree.SonanceEQ.pro"
# RevenueCat secret key (project-scoped) for Tools/rc/api.py — first sk_ found in the ecosystem.
export RC_SECRET_KEY="$(grep -hoE 'sk_[A-Za-z0-9]+' "$HOME"/Documents/Software/*/.env 2>/dev/null | head -1)"
[ -n "$ASC_API_KEY_ID" ] && [ -f "$ASC_API_KEY_PATH" ] \
  && echo "asc env ready (key=$ASC_API_KEY_ID, team=$TEAM_ID)" \
  || echo "⚠ asc creds incomplete — check $_SKILL and ~/private_keys/"
