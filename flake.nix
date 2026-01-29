{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      eachSystem = lib.genAttrs systems;
      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          localSystem.system = system;
          overlays = [ (import rust-overlay) ];
        }
      );

      cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
      cargoPackageVersion = cargoToml.package.version;

      commitHash = self.shortRev or self.dirtyShortRev or "unknown";

      version = "${cargoPackageVersion}-${commitHash}";
    in
    {
      packages = lib.mapAttrs (
        system: pkgs:
        let
          buildXwaylandSatellite =
            {
              lib,
              rustPlatform,
              pkg-config,
              makeBinaryWrapper,
              libxcb,
              xcb-util-cursor,
              xwayland,
              withSystemd ? true,
            }:

            rustPlatform.buildRustPackage rec {
              pname = "xwayland-satellite";
              inherit version;

              src = self;

              cargoLock = {
                lockFile = "${src}/Cargo.lock";
                allowBuiltinFetchGit = true;
              };

              nativeBuildInputs = [
                rustPlatform.bindgenHook
                pkg-config
                makeBinaryWrapper
              ];

              buildInputs = [
                libxcb
                xcb-util-cursor
              ];

              buildNoDefaultFeatures = true;
              buildFeatures = lib.optional withSystemd "systemd";

              postPatch = ''
                substituteInPlace resources/xwayland-satellite.service \
                  --replace-fail '/usr/local/bin' "$out/bin"
              '';

              postInstall = lib.optionalString withSystemd ''
                install -Dm0644 resources/xwayland-satellite.service -t $out/lib/systemd/user
              '';

              postFixup = ''
                wrapProgram $out/bin/xwayland-satellite \
                  --prefix PATH : "${lib.makeBinPath [ xwayland ]}"
              '';

              doCheck = false;

              meta = {
                description = "Xwayland outside your Wayland";
                homepage = "https://github.com/Supreeeme/xwayland-satellite";
                license = lib.licenses.mpl20;
                mainProgram = "xwayland-satellite";
                platforms = lib.platforms.linux;
              };
            };
        in
        {
          xwayland-satellite = pkgs.callPackage buildXwaylandSatellite { };
          default = self.packages.${system}.xwayland-satellite;
        }
      ) pkgsFor;

      devShells = lib.mapAttrs (_: pkgs: {
        default = (pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }) {
          buildInputs = with pkgs; [
            rustPlatform.bindgenHook
            rust-bin.stable.latest.default
            pkg-config

            xcb-util-cursor
            xorg.libxcb
            xwayland
          ];
        };
      }) pkgsFor;

      formatter = lib.mapAttrs (_: pkgs: pkgs.nixfmt) pkgsFor;
    };
}
