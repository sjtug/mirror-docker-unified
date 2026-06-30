{
  lib,
  nix2container,
}:
let
  # Helper: build ordered OCI image layers where each layer depends on
  # all prior layers.  This lets nix2container deduplicate store paths
  # that are shared across layers.
  #
  #   layers = foldImageLayers [
  #     { deps = [ bash coreutils ]; }
  #     { deps = [ my-binary ]; }
  #   ];
  foldImageLayers =
    let
      mergeToLayer =
        priorLayers: component:
        assert builtins.isList priorLayers;
        assert builtins.isAttrs component;
        let
          layer = nix2container.buildLayer (
            component
            // {
              layers = priorLayers;
            }
          );
        in
        priorLayers ++ [ layer ];
    in
    layers: lib.foldl mergeToLayer [ ] layers;
in
{
  inherit foldImageLayers;
}
