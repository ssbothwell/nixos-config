{
  inputs = {
    nixpkgs.url = github:nixos/nixpkgs/nixos-unstable;
    unstable.url = github:nixos/nixpkgs;

    flake-utils = {
      url = github:numtide/flake-utils;
    };

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.90.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = github:nix-community/home-manager;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = github:nix-community/disko;
      inputs.nixpkgs.follows = "unstable";
    };

    sops-nix = {
      url = github:Mic92/sops-nix;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = github:nix-community/nixos-generators;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = github:NixOS/nixos-hardware/master;
    };

    brightness-bar = {
      url = github:solomon-b/brightness-bar;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    volume-bar = {
      url = github:solomon-b/volume-bar;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    xmonad-solomon = {
      url = github:solomon-b/xmonad-solomon;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.unstable.follows = "unstable";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , unstable
    , flake-utils
    , lix-module
    , home-manager
    , disko
    , sops-nix
    , nixos-hardware
    , nixos-generators
    , brightness-bar
    , volume-bar
    , xmonad-solomon
    ,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;

        config = {
          allowUnfree = true;
        };

        overlays = with inputs; [
          brightness-bar.overlays.default
          volume-bar.overlays.default
          xmonad-solomon.overlays.default
          xmonad-solomon.overlays.xmonad
          xmonad-solomon.overlays.xmonad-contrib
          # (final: prev: { eww = eww.packages.${final.system}.default; })
        ];
      };

      mkServer = targetHost: { config, ... }: {
        deployment = {
          inherit targetHost;
          #targetUser = config.primary-user.name;
          tags = [ "server" ];
          allowLocalDeployment = false;
        };

        imports = [
          "${toString config/machines/servers}/${targetHost}"
          nixpkgs.nixosModules.notDetected
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
          disko.nixosModules.disko
        ];

        sops = {
          defaultSopsFile = ./secrets.yaml;
          secrets.primary-user-password = { };
        };
      };
    in
    {
      formatter."${system}" = pkgs.nixpkgs-fmt;
      devShells."${system}".default = pkgs.mkShell {
        nativeBuildInputs = [ pkgs.colmena pkgs.nixfmt pkgs.sops ];
      };

      packages.x86_64-linux = {
        # NixOS boot disk with my SSH Keys integrated
        nixos-iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "install-iso";
          modules = [
            ./installer
            home-manager.nixosModules.home-manager
            lix-module.nixosModules.default
          ];
        };

        # NixOS-Anywhere provisioning script for physical machines.
        # nix run '.#install-pc'
        install-pc =
          let
            src = builtins.readFile ./installer/install-pc.sh;

            script = (pkgs.writeScriptBin "install-pc" src).overrideAttrs (old: {
              buildCommand = "${old.buildCommand}\n patchShebangs $out";
            });
          in
          pkgs.symlinkJoin {
            name = "install-pc";
            paths = [ pkgs.gum pkgs.jq pkgs.pass script ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/install-pc --prefix PATH : $out/bin";
          };

        # NixOS-Anywhere provisioning script for virtual machines and remote servers.
        # nix run '.#install-server'
        install-server =
          let
            src = builtins.readFile ./installer/install-server.sh;

            script = (pkgs.writeScriptBin "install-server" src).overrideAttrs (old: {
              buildCommand = "${old.buildCommand}\n patchShebangs $out";
            });
          in
          pkgs.symlinkJoin {
            name = "install-server";
            paths = [ pkgs.gum pkgs.jq pkgs.pass script ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/install-server --prefix PATH : $out/bin";
          };

        deploy = pkgs.writeShellScriptBin "deploy" ''
          servers=$(ls config/machines/servers)
          all="servers"
          machine=$(echo "$servers" | ${pkgs.gum}/bin/gum choose)
          echo "Deploying '$machine'"
          ${pkgs.colmena}/bin/colmena apply --on $machine
        '';

        deploy-all = pkgs.writeShellScriptBin "deploy-all" ''
          ${pkgs.colmena}/bin/colmena apply --on @server
        '';
      };

      apps.x86_64-linux = {
        deploy = flake-utils.lib.mkApp { drv = self.packages.${system}.deploy; };
        deploy-all = flake-utils.lib.mkApp { drv = self.packages.${system}.deploy-all; };
        default = self.apps.${system}.deploy;
      };

      nixosConfigurations = {
        lorean = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          modules = [
            ./config/machines/personal-computers/lorean
            ({ ... }: {
              sops = {
                defaultSopsFile = ./secrets.yaml;
                secrets.primary-user-password = { };
              };
            })
            nixpkgs.nixosModules.notDetected
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            lix-module.nixosModules.default
          ];

          specialArgs = { inherit inputs; };
        };

        nightshade = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          modules = [
            ./config/machines/personal-computers/nightshade
            ({ ... }: {
              sops = {
                defaultSopsFile = ./secrets.yaml;
                secrets.primary-user-password = { };
              };
            })
            nixpkgs.nixosModules.notDetected
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            nixos-hardware.nixosModules.framework-11th-gen-intel
            lix-module.nixosModules.default
          ];

          specialArgs = { inherit inputs; };
        };

        zodiacal-light = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          modules = [
            ./config/machines/personal-computers/zodiacal-light
            ({ ... }: {
              sops = {
                defaultSopsFile = ./secrets.yaml;
                secrets.primary-user-password = { };
              };
            })
            nixpkgs.nixosModules.notDetected
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            nixos-hardware.nixosModules.dell-xps-15-9520-nvidia
            lix-module.nixosModules.default
          ];

          specialArgs = { inherit inputs; };
        };

        gnostic-ascension = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          modules = [
            ./config/machines/servers/gnostic-ascension
            ({ ... }: {
              sops = {
                defaultSopsFile = ./secrets.yaml;
                secrets.primary-user-password = { };
              };
            })
            nixpkgs.nixosModules.notDetected
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            lix-module.nixosModules.default
          ];

          specialArgs = { inherit inputs; };
        };

        test-vm = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          modules = [
            ./config/machines/servers/test-vm
            ({ ... }: {
              sops = {
                defaultSopsFile = ./secrets.yaml;
                secrets.primary-user-password = { };
              };
            })
            nixpkgs.nixosModules.notDetected
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
          ];

          specialArgs = { inherit inputs; };
        };
      };

      colmena =
        let
          configs = self.nixosConfigurations;
        in
        {
          meta = {
            nixpkgs = pkgs;
            specialArgs = {
              inherit inputs;
            };
            nodeNixpkgs = builtins.mapAttrs (name: value: value.pkgs) configs;
            nodeSpecialArgs = builtins.mapAttrs (name: value: value._module.specialArgs) configs;
          };
        } // builtins.mapAttrs (machine: _: mkServer machine) (builtins.readDir ./config/machines/servers)
        // builtins.mapAttrs
          (name: value: {
            deployment = {
              targetHost = name;
              tags = [ "pc" ];
              allowLocalDeployment = true;
            };
            imports = value._module.args.modules;
          })
          configs;
    };
}
