# Check if app exists in the state `packages` attr, regardless of
# statefile format and handling mixed arrays
if $old.packages == null then
  false
elif ($old.packages | length == 0) then
  false
else
  # Handle packages array with potentially mixed formats
  $old.packages | any(
    if type == "string" then
      . == $appId
    elif type == "object" and has("appId") then
      .appId == $appId
    else
      false
    end
  )
end