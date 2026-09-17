{
  description = "Bend: a dependently typed, affine language";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";

  inputs.bend2 = {
    url = "github:bendlang/bend";
    flake = false;
  };

  outputs = { self, nixpkgs, bend2 }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in {
      packages = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) lib;
          bend = pkgs.stdenvNoCC.mkDerivation {
            pname = "bend";
            version = lib.head (builtins.match ".*const VERSION = \"([^\"]+)\";.*"
              (builtins.readFile "${bend2}/bend2/main.ts"));
            src = bend2;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/share/bend/bend2" "$out/share/bend/guide" "$out/bin"
              cp bend2/{bend,comp,main}.ts bend2/base.bend "$out/share/bend/bend2/"
              cp -r bend2/effs "$out/share/bend/bend2/"
              cp guide/GUIDE.md "$out/share/bend/guide/"
              cp LICENSE "$out/share/bend/"
              makeWrapper ${lib.getExe pkgs.bun} "$out/bin/bend" \
                --add-flags "$out/share/bend/bend2/main.ts" \
                --suffix PATH : ${lib.makeBinPath [ pkgs.clang ]}
              runHook postInstall
            '';
            meta = {
              description = "Dependently typed, affine language with parallel CPU and GPU runtimes";
              homepage = "https://bend-lang.com";
              license = lib.licenses.asl20;
              platforms = systems;
              mainProgram = "bend";
            };
          };
        in { inherit bend; default = bend; });

      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.bend}/bin/bend";
          meta.description = self.packages.${system}.bend.meta.description;
        };
      });

      devShells = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          bend = self.packages.${system}.bend;
        in {
          default = (pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }) {
            packages = [ bend pkgs.bun pkgs.gnumake ];
            buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.libx11 pkgs.alsa-lib
            ];
            BEND2_CORE = "${bend}/share/bend";
            BEND_MAIN = "${bend}/share/bend/bend2/main.ts";
          };
        });

      checks = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          bend = self.packages.${system}.bend;
        in {
          cli = pkgs.runCommand "bend-cli-check" {
            nativeBuildInputs = [ bend pkgs.bun ];
            CC = "${pkgs.clang}/bin/clang";
          } ''
            export HOME="$TMPDIR"
            bend --version | grep -Fx 'bend ${bend.version}'
            bend guide > guide.md
            cmp guide.md ${bend}/share/bend/guide/GUIDE.md
            cp ${bend2}/tests/io/text_formatting.bend main.bend
            sed -n 's/^#|//p' main.bend > expected
            bend main.bend > actual
            cmp expected actual
            bend main.bend -o main.js
            bun main.js > actual
            cmp expected actual
            bend main.bend -o main
            ./main --gpu off > actual
            cmp expected actual
            touch "$out"
          '';
        });
    };
}
