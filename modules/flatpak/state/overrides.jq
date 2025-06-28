# Flatpak Overrides Merge Script
#
# This script merges Flatpak override configurations from multiple sources:
# - base_overrides: Base configuration from override files
# - active: Currently active overrides (existing state)
# - old_state: Previous declarative state
# - new_state: New declarative state
#
# Merge Logic:
# The script applies changes on top of base configuration while preserving
# manual modifications that weren't part of the previous declarative state.
#
# For each entry, the merge formula is:
#   base + (active - old) + new
#
# Where:
# - base: Always preserved from override files
# - active - old: Manual changes (active values not from old state)
# - new: New declarative state values
#
# Special handling:
# - If new value is a string: Completely replaces the merged array
# - If new value is an array: Merges with base and filtered active values
# - Arrays are deduplicated and sorted alphabetically
#
# Input parameters:
# - $app_id: Application identifier
# - $base_overrides: Base configuration from files
# - $active: Currently active overrides
# - $old_state: Previous state for this app
# - $new_state: New state for this app

# Convert entry value into array for consistent processing
def values($value):
  if ($value | type) == "string" then
    $value | split(";") | map(select(. != "" and . != null))
  else
    ($value // [])
  end;

# Extract state aliases for the current app
($old_state.overrides[$app_id] // {}) as $old
| ($new_state.overrides[$app_id] // {}) as $new
# Process all sections that exist in base, active, or new state
| $base_overrides + $active + $new
| keys
| map(
    . as $section
    | {
        "section_key": $section,
        "section_value": (
          # Process all entries that exist in base, active, or new state for this section
          ($base_overrides[$section] // {}) + ($active[$section] // {}) + ($new[$section] // {})
          | keys
          | map(
              . as $entry
              | {
                  "entry_key": $entry,
                  "entry_value": (
                    # Extract value aliases for current entry
                    $base_overrides[$section][$entry] as $base_value
                    | $active[$section][$entry] as $active_value
                    | $new[$section][$entry] as $new_value
                    | $old[$section][$entry] as $old_value
                    # Apply merge logic
                    | if ($new_value | type) == "string" then
                        # String values completely override arrays
                        $new_value
                      else
                        # Array merge: base + (active - old) + new
                        values($base_value) + (values($active_value) - values($old_value)) + values($new_value)
                        # Remove empty arrays and deduplicate/sort values
                        | select(. != [])
                        | map(select(. != ""))
                        # Remove duplicates and empy values, while preserving the original value order in output configs
                        | . as $arr | reduce .[] as $item ([]; if . | contains([$item]) then . else . + [$item] end)
                        # Convert array back to Flatpak string format
                        | join(";")
                      end
                  )
                }
            )
          # Remove entries with empty values
          | select(. != [])
        )
      }
  )[]

# Generate the final INI-format overrides file
| "[\(.section_key)]", (.section_value[] | "\(.entry_key)=\(.entry_value)"), ""