# Check if app exists in the state `packages` attr, regardless of
# statefle format
if $old.packages == null then
    false
elif ($old.packages | length > 0) and ($old.packages[0] | type == "string") then
    # Old format: list of strings
    $old.packages | index($appId) != null
elif ($old.packages | length > 0) and ($old.packages[0] | type == "object") then
    # New format: list of objects with appId field
    $old.packages | map(.appId) | index($appId) != null
else
    false
end