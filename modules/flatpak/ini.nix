{lib}: let
  trimStr = s: let
    m = builtins.match "[[:space:]]*(.*[^[:space:]]|)[[:space:]]*" s;
  in
    if m == null
    then ""
    else builtins.elemAt m 0;

  # Parse a flatpak INI file into a nix attrset with the same shape as
  # overrides.settings:
  #
  #   { SectionName = { key = string_or_list; ... }; ... }
  #
  # - Keys and values are whitespace-trimmed.
  # - Semicolon-separated values become a list; single values stay as a string.
  # - Blank lines and lines starting with '#' or ';' are ignored.
  parseIniContent = content: let
    lines = lib.splitString "\n" content;
  in
    (builtins.foldl' (
        acc: rawLine: let
          line = trimStr rawLine;
          isComment = lib.hasPrefix "#" line || lib.hasPrefix ";" line;
          isEmpty = line == "";
          isSection =
            !isComment
            && !isEmpty
            && lib.hasPrefix "[" line
            && lib.hasSuffix "]" line;
          sectionName = lib.removeSuffix "]" (lib.removePrefix "[" line);
          kvMatch = builtins.match "^([^=]+)=(.*)$" line;
          isKV = kvMatch != null && !isSection;
          key = trimStr (builtins.elemAt kvMatch 0);
          rawValue = trimStr (builtins.elemAt kvMatch 1);
          values = builtins.filter (s: s != "") (lib.splitString ";" rawValue);
          parsedValue =
            if builtins.length values > 1
            then values
            else rawValue;
        in
          if isSection
          then acc // {section = sectionName;}
          else if isKV && acc.section != null
          then
            acc
            // {
              sections =
                acc.sections
                // {
                  ${acc.section} =
                    (acc.sections.${acc.section} or {})
                    // {
                      ${key} = parsedValue;
                    };
                };
            }
          else acc
      ) {
        section = null;
        sections = {};
      }
      lines).sections;

  # Serialize a nix attrset (overrides.settings shape) back to flatpak INI format.
  # Sections and keys are emitted in alphabetical order; list values are joined with ';'.
  toIniContent = attrs: let
    sections = builtins.sort (a: b: a < b) (builtins.attrNames attrs);
    renderValue = v:
      if builtins.isList v
      then builtins.concatStringsSep ";" v
      else v;
    renderEntry = section: key: "${key}=${renderValue attrs.${section}.${key}}";
    renderSection = section: let
      keys = builtins.sort (a: b: a < b) (builtins.attrNames attrs.${section});
    in
      "[${section}]\n" + builtins.concatStringsSep "\n" (map (renderEntry section) keys) + "\n";
  in
    builtins.concatStringsSep "\n" (map renderSection sections);
  # Merge two parsed INI attrsets (eg. `settings` and `fileSettings`) for a single appId.
  # `settings` wins over `fileSettings` for any key present in both.
  # Returns a merged attrset in the same shape as `overrides.settings`.
  mergeOverrideSettings = settings: fileSettingsByApp: appId: let
    s = settings.${appId} or {};
    f = fileSettingsByApp.${appId} or {};
    sections = lib.lists.unique (builtins.attrNames s ++ builtins.attrNames f);
    mergedSection = sec: let
      allKeys = lib.lists.unique (
        builtins.attrNames (s.${sec} or {})
        ++ builtins.attrNames (f.${sec} or {})
      );
    in
      builtins.listToAttrs (map (k: {
          name = k;
          value =
            if s ? ${sec} && s.${sec} ? ${k}
            then s.${sec}.${k}
            else f.${sec}.${k};
        })
        allKeys);
  in
    builtins.listToAttrs (map (sec: {
        name = sec;
        value = mergedSection sec;
      })
      sections);
in {
  inherit parseIniContent toIniContent mergeOverrideSettings;
}
