{
  description = "Seicento 900 Cup: Godot 4.7.2 racing game (dev shell and runner for NixOS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # nixpkgs builds Godot from source and links Vulkan, GL, X11, Wayland, ALSA,
      # PulseAudio, fontconfig and speech-dispatcher itself. The project is made with 4.7.2.
      godotFor = pkgs:
        assert lib.assertMsg (lib.versionAtLeast pkgs.godot_4.version "4.7.2")
          "Seicento needs Godot 4.7.2, nixpkgs has ${pkgs.godot_4.version}";
        pkgs.godot_4;

      # The same Godot rebuilt for x86_64 CPUs without SSE4.2 (AMD K10/Llano and older,
      # e.g. an E2-3000M): upstream compiles with -msse4.2 -mpopcnt, so it dies with
      # "Illegal instruction" there. This drops to the SSE3 baseline and skips LTO and
      # debug symbols so it links on a small machine. No binary cache has it: it is a
      # long from-source build (hours on a 2-core laptop).
      godotNoSse42For = pkgs: (godotFor pkgs).overrideAttrs (old: {
        pname = "godot-nosse42";
        separateDebugInfo = false;
        outputs = lib.remove "debug" old.outputs;
        sconsFlags = lib.filter (f: f != "debug_symbols=true") old.sconsFlags
          ++ [ "debug_symbols=false" "lto=none" ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace SConstruct \
            --replace-fail 'env.Append(CCFLAGS=["-msse4.2", "-mpopcnt"])' 'env.Append(CCFLAGS=["-msse3"])'
          # the start-up CPU check wants SSE4.2 (CPUID.1 ECX bit 20); ask for SSE3 (bit 0)
          substituteInPlace platform/linuxbsd/godot_linuxbsd.cpp \
            --replace-fail 'if (!(cpuinfo[2] & (1 << 20))) {' 'if (!(cpuinfo[2] & (1 << 0))) {'
        '';
      });

      # Opens the game from the repository root; extra arguments go to Godot.
      # SEICENTO_RENDERING_DRIVER (vulkan / opengl3) picks the renderer; `driver` is its default.
      # Old machines want opengl3: on a GPU without Vulkan (pre-GCN Radeon) Godot finds Mesa's
      # lavapipe CPU Vulkan instead of falling back to OpenGL, and draws nothing for minutes.
      runnerFor = pkgs: godot: driver: pkgs.writeShellApplication {
        name = "seicento";
        runtimeInputs = [ godot ];
        text = ''
          root="''${SEICENTO_ROOT:-$PWD}"
          if [ ! -f "$root/godot/project.godot" ]; then
            echo "seicento: run from the repository root (or set SEICENTO_ROOT)" >&2
            exit 1
          fi
          driver="''${SEICENTO_RENDERING_DRIVER:-${driver}}"
          exec godot --path "$root/godot" ''${driver:+--rendering-driver "$driver"} "$@"
        '';
      };

      shellFor = pkgs: godot: pkgs.mkShell {
        packages = [
          godot
          (pkgs.python3.withPackages (ps: [ ps.numpy ])) # tools/*.py
        ];
      };
    in {
      packages = forAll (pkgs: {
        godot = godotFor pkgs;
        godot-nosse42 = godotNoSse42For pkgs;
        default = runnerFor pkgs (godotFor pkgs) "";
        nosse42 = runnerFor pkgs (godotNoSse42For pkgs) "opengl3";
      });

      apps = forAll (pkgs: {
        default = { type = "app"; program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default; };
        nosse42 = { type = "app"; program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nosse42; };
      });

      devShells = forAll (pkgs: {
        default = shellFor pkgs (godotFor pkgs);
        nosse42 = shellFor pkgs (godotNoSse42For pkgs);
      });
    };
}
