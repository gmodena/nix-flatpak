# Flatpak Overrides Merge Script
#
# Merge precedence (highest to lowest):
# 1. overrides.settings     - declarative Nix settings
# 2. overrides._fileSettings - settings from override files (parsed at evaluation time)
# 3. active overrides        - existing override file in the install dir (direct edits)
#
# For each key in each section, the highest-priority source that defines the key wins.
# When a setting or file is removed from the Nix config, the corresponding entry in the
# active override file is preserved only if it was a direct user edit. Keys that
# were previously written by nix-flatpak via overrides.files (_fileSettings) are retracted
# when the file is removed from the config.
#
# Input parameters:
# - $app_id:    Application identifier
# - $active:    Currently active overrides from the override install dir
# - $new_state: New declarative state (contains .overrides.settings and .overrides._fileSettings)
# - $old_state: Previous declarative state (used to detect stale _fileSettings keys)

# Normalize a value to a semicolon-joined string for INI output.
def normalize:
  if type == "array" then
    map(select(. != "" and . != null)) | join(";")
  else
    (. // "")
  end;

# Support both v2 format (overrides.settings) and legacy v1 format (overrides directly on app keys)
($new_state.overrides.settings[$app_id] // $new_state.overrides[$app_id] // {}) as $settings
| ($new_state.overrides._fileSettings[$app_id] // {}) as $file_settings
| ($old_state.overrides._fileSettings[$app_id] // {}) as $old_file_settings

# Collect all sections from all three sources
| ([ ($settings | keys[]), ($file_settings | keys[]), ($active | keys[]) ] | unique)
| map(
    . as $section
    | {
        "section_key": $section,
        "section_value": (
          [ (($settings[$section] // {}) | keys[]),
            (($file_settings[$section] // {}) | keys[]),
            (($active[$section] // {}) | keys[]) ]
          | unique
          | map(
              . as $entry
              | ($settings[$section][$entry]) as $s
              | ($file_settings[$section][$entry]) as $f
              | ($active[$section][$entry]) as $a
              # Strict precedence: settings wins, then file_settings, then active.
              # Active keys that were previously written by _fileSettings (old_file_settings)
              # but are no longer claimed by any Nix config are retracted, not preserved.
              # Active keys from direct edits  are preserved.
              | if $s != null then { "entry_key": $entry, "entry_value": ($s | normalize) }
                elif $f != null then { "entry_key": $entry, "entry_value": ($f | normalize) }
                elif $a != null and ($old_file_settings[$section][$entry] == null) then
                  { "entry_key": $entry, "entry_value": ($a | normalize) }
                else empty
                end
            )
          | map(select(.entry_value != ""))
        )
      }
    | select(.section_value | length > 0)
  )
| .[]

# Generate the final INI overrides file
| "[\(.section_key)]", (.section_value[] | "\(.entry_key)=\(.entry_value)"), ""
