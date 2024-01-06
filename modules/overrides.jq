# Convert entry value into array
def values($value): if ($value | type) == "string" then [$value] else ($value // []) end;

# State aliases
  ($old_state.overrides[$app_id] // {}) as $old
| ($new_state.overrides[$app_id] // {}) as $new

# Map sections that exist in either active or new state (ignore old)
| $active + $new | keys | map (
  . as $section | {"section_key": $section, "section_value": (

      # Map entries that exist in either active or new state (ignore old)
      ($active[$section] // {}) + ($new[$section] // {}) | keys | map (
        . as $entry | { "entry_key": $entry, "entry_value": (

            # Entry value aliases
              $active[$section][$entry] as $active_value
            | $new[$section][$entry]    as $new_value
            | $old[$section][$entry]    as $old_value

            # Use new value if it is a string
            | if ($new_value | type) == "string" then $new_value
              else
                # Otherwise remove old values from the active ones, and add the new ones
                values($active_value) - values($old_value) + values($new_value)

                # Remove empty arrays and duplicate values
                | select(. != []) | unique
                
                # Convert array into Flatpak string array format
                | join(";")
              end
          )}
        )

      # Remove empty arrays
      | select(. != [])
    )}
  )[]

# Generate the final overrides file
| "[\(.section_key)]", (.section_value[] | "\(.entry_key)=\(.entry_value)"), ""
