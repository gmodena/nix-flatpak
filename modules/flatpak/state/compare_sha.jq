# compare_sha.jq - Flatpak bundle nix store SHA256 change
#
# PURPOSE:
#   Compares nis store SHA256 values for a specific Flatpak bundle between two state snapshots.
#   Returns the application ID if SHA256 has changed, empty output if unchanged.
#
# USAGE:
#   jq -n --argjson oldState '<JSON>' --argjson newState '<JSON>' --arg appId '<APP_ID>' -f compare_sha.jq
#
# PARAMETERS:
#   $oldState  - Previous state JSON with packages array
#   $newState  - Current state JSON with packages array  
#   $appId     - Application ID to compare (e.g., "io.github.softfever.OrcaSlicer")
#
# INPUT FORMAT:
#   {"packages":[{"appId":"com.example.App","sha256":"hash_value"},...]}
#
# OUTPUT:
#   "app.id.string" - When SHA256 changed (including null transitions)
#   (empty)         - When SHA256 unchanged
#
# EXAMPLES:
#   Change detected:     "abc123" → "def456" or "abc123" → null
#   No change:          "abc123" → "abc123" or null → null

# Find package by appId and extract sha256

def find_package_sha(state; appId):
  if state.packages then
    (state.packages | map(select(.appId == appId)) | .[0].sha256 // null)
  else
    null
  end;

# Main comparison logic - returns appId if changed, empty if not
(find_package_sha($oldState; $appId)) as $old_sha |
(find_package_sha($newState; $appId)) as $new_sha |
if ($old_sha != $new_sha) then $appId else empty end