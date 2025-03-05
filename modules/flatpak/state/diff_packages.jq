# Extract app IDs regardless of format
def getAppIds(packages):
  if packages == null then []
    elif (packages | length > 0) and (packages[0] | type == "string") then
      # Old format: list of strings
      packages
    elif (packages | length > 0) and (packages[0] | type == "object") then
      # New format: list of objects with appId field
      packages | map(.appId)
    else []
end;

# Get app IDs from both old and new state
(getAppIds($old.packages) - getAppIds($new.packages))[]