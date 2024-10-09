# utiliy function to manage flatpakref files
{ pkgs, lib, ... }:
let
  # check if a value is a string
  isString = value: builtins.typeOf value == "string";

  # Check if a package declares a flatpakref
  isFlatpakref = { flatpakref, ... }:
    flatpakref != null && isString flatpakref;

  # sanitize a URL to be used as a key in an attrset.
  sanitizeUrl = url: builtins.replaceStrings [ "https://" "/" "." ":" ] [ "https_" "_" "_" "_" ] url;

  # Fetch and convert an ini-like flatpakref file into an attrset, and cache it for future use
  # within the same activation.
  # We piggyback on builtins.fetchurl to fetch and cache flatpakref file. Pure nix evaluations
  # requrie a sha256 hash to be provided.
  # TODO: extract a generic ini-to-attrset function.
  flatpakrefToAttrSet = { flatpakref, sha256, ... }: cache:
    let
      updatedCache =
        if builtins.hasAttr (sanitizeUrl flatpakref) cache then
          cache
        else
          let
            fetchurlArgs =
              if sha256 != null
              then { url = flatpakref; sha256 = sha256; }
              else { url = flatpakref; };
            iniContent = builtins.readFile (builtins.fetchurl fetchurlArgs);
            lines = builtins.split "\r?\n" iniContent;
            parsed = builtins.filter (line: line != null) (map (line: builtins.match "(.*)=(.*)" (builtins.toString line)) lines);

            # Convert the list of key-value pairs into an attrset
            attrSet = builtins.listToAttrs (map (pair: { name = builtins.elemAt pair 0; value = builtins.elemAt pair 1; }) parsed);
          in
          cache // { ${(sanitizeUrl flatpakref)} = attrSet; };
    in
    updatedCache;
in
{
  inherit isFlatpakref sanitizeUrl flatpakrefToAttrSet;
}
