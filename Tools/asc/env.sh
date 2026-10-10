# Source this before an asc/ script: source Tools/asc/env.sh
# RevenueCat credentials and project/app selection must be supplied separately.
# Pulls the App Store Connect API creds from the ios-deploy skill + the .p8 on disk (living off the land).
# Nothing secret is hardcoded here; values are read at runtime.
_SKILL="$HOME/Documents/Software/skills/ios-deploy/SKILL.md"
export ASC_API_KEY_ID="$(grep -i 'ASC Key ID' "$_SKILL" | grep -oE '[A-Z0-9]{10}' | head -1)"
export ASC_API_ISSUER_ID="$(grep -i 'ASC Issuer ID' "$_SKILL" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -1)"
export ASC_API_KEY_PATH="$HOME/private_keys/AuthKey_${ASC_API_KEY_ID}.p8"
export TEAM_ID="Y4HDXFWXUV"
export APP_BUNDLE_ID="com.isaiahdupree.SonanceEQ"
export IAP_PRODUCT_ID="com.isaiahdupree.SonanceEQ.pro"
[ -n "$ASC_API_KEY_ID" ] && [ -f "$ASC_API_KEY_PATH" ] \
  && echo "asc env ready (key=$ASC_API_KEY_ID, team=$TEAM_ID)" \
  || echo "⚠ asc creds incomplete — check $_SKILL and ~/private_keys/"
