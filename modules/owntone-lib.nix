{ lib }:
let
  inherit (lib)
    filterAttrs
    isAttrs
    isBool
    isFloat
    isInt
    isList
    strings;

  escapeString = str:
    strings.replaceStrings [ "\\" "\"" "\n" "\t" ] [ "\\\\" "\\\"" "\\n" "\\t" ] str;

  renderString = str: "\"${escapeString str}\"";

  renderValue = value:
    if value == null then ""
    else if isBool value then (if value then "true" else "false")
    else if isInt value || isFloat value then toString value
    else if isList value then "{ ${strings.concatStringsSep ", " (map renderValue value)} }"
    else if builtins.typeOf value == "path" then renderString (toString value)
    else if builtins.typeOf value == "string" then renderString value
    else throw "Unsupported Owntone config value type: ${builtins.typeOf value}";

  indentStep = "  ";

  renderBlock = indent: name: attrs:
    let
      cleanedAttrs = filterAttrs (_: v: v != null) attrs;
      keys = builtins.attrNames cleanedAttrs;
      renderEntry = key: val:
        if isList val && (val != [ ]) && lib.all isAttrs val then
          strings.concatStringsSep "\n\n" (map (renderBlock (indent + indentStep) key) val)
        else if isAttrs val then renderBlock (indent + indentStep) key val
        else "${indent}${indentStep}${key} = ${renderValue val}";
      body =
        strings.concatMapStringsSep "\n" (line: line)
          (builtins.filter (line: line != "") (map (k: renderEntry k cleanedAttrs.${k}) keys));
    in if name == "" then body else
      let
        parts =
          [ "${indent}${name} {" ]
          ++ (if body == "" then [ ] else [ body ])
          ++ [ "${indent}}" ];
      in strings.concatStringsSep "\n" parts;

  renderConfigBlocks = attrs:
    let
      blocks = builtins.attrNames (filterAttrs (_: v: v != null) attrs);
      renderedBlocks = map (name: renderBlock "" name attrs.${name}) blocks;
    in strings.concatStringsSep "\n\n" renderedBlocks;
in {
  renderConfig = config: renderConfigBlocks config;
}
