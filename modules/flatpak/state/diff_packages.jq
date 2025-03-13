def getAppIds(packages):
  if packages == null then []
  else
    packages | map(
      # Old format
      if type == "string" then .
      # Modern format
      elif type == "object" and has("appId") then .appId
      else null
      end
    ) | map(select(. != null))
  end
;

# Generate the difference between `old` and `new` states.
getAppIds($old.packages) - getAppIds($new.packages) | if length > 0 then .[] else empty end