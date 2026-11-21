# For nix-shell users without flakes: the flake's dev shell, through flake-compat.
#   nix-shell             Godot 4.7.2 from nixpkgs (+ python3 with numpy)
#   nix-shell -A nosse42  the same Godot rebuilt for CPUs without SSE4.2
let
  flake = (import (fetchTarball {
    url = "https://github.com/edolstra/flake-compat/archive/refs/tags/v1.1.0.tar.gz";
    sha256 = "19d2z6xsvpxm184m41qrpi1bplilwipgnzv9jy17fgw421785q1m";
  }) { src = ./.; }).defaultNix;
  shells = flake.devShells.${builtins.currentSystem};
in
shells.default // { inherit (shells) nosse42; }
