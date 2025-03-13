# A backward compatible jq query to parse state
# configuration in legacy and modern (format >=v1.0.0)
# nix-flatpak state-files.
# If a state-file is already in modern format, return
# it "as is", by projecting its fields.
# Otherwise, convert to legacy to modern format by 
# adding properties at runtime (or placeholders)
# The query supports merging managend and unmanaged state.
# Managed is loaded from config and previous state files;
# Unmanaged is generated at runtime by quering the flatpak
# installation.
# See modules/flatpak/install.nix for details

# Check format of existing packages
def isNewFormat:
  if (has("packages") and (.packages | length > 0) and (.packages[0] | type == "object"))
  then true
  else false
  end;

# Extract a remote attrSet from a list
# of all currently installed remotes ($installed_remotes)
def extractRemoteAttrs:
  (split("\n") | map(select(length > 0) | split("\t")) |
    map({
      "name": .[0]
    }));

# Extract packages attrSet from a list
# of currently installed packages ($installed_packages)
def extractPackageAttrs(old_packages; installed_packages):
  (
    old_packages + 
    (installed_packages | split("\n") | map(select(length > 0) | split("\t")) |
      map({
        "appId": .[0],
        "origin": .[1],
        "commit": .[2]
      }))
  ) | unique_by(.appId);

if ($old | isNewFormat) then
    # Already in new format. Keep state as is.
    $old + {
      "packages": extractPackageAttrs($old.packages; $installed_packages),
      "remotes": ($installed_remotes | extractRemoteAttrs)
    }
else
    # Old format, convert while adding new keys
    $old + {
      "packages": extractPackageAttrs(
        (($old.packages // []) | map({
          "appId": .,
          "origin": null,
          "commit": null
        }));
        $installed_packages
      ),
      "remotes": ($installed_remotes | extractRemoteAttrs)
    }
end