{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./kmonad.nix
    ./mpd.nix
    ./nfs.nix
    ./zfs.nix

    ../../../profiles/pc
    ../../../modules/services/virtualisation/libvirt
    ../../../modules/system/devices/touchpad
    ../../../modules/system/powertop
  ];

  nix.package = pkgs.nixUnstable;
  nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';

  environment.systemPackages = [
    pkgs.acpi
  ];

  primary-user.name = "solomon";

  sops.secrets.syncoid-ssh-key = {
    owner = "syncoid";
    mode = "600";
  };

  networking = {
    hostName = "nightshade";
    hostId = "997f3c8d";
    networkmanager.enable = true;

    useDHCP = false;
    interfaces.wlp170s0.useDHCP = true;
  };

  services.printing.enable = true;
  services.avahi.enable = true;
  # Important to resolve .local domains of printers, otherwise you get an error
  # like  "Impossible to connect to XXX.local: Name or service not known"
  services.avahi.nssmdns = true;
}
