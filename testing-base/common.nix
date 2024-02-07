# configuration.nix
{ config, lib, pkgs, ... }: {
  users.users.antani = {
    isNormalUser = true;
    home = "/home/antani";
    extraGroups = [ "wheel" ]; # Enables `sudo` for the user.
    password = "changeme"; # The password assigned if the user does not already exist.
  };

  virtualisation.vmVariant = {
    # following configuration is added only when building VM with build-vm
    virtualisation = {
      memorySize = 1024; # Use 1024MiB memory.
      cores = 2;
      graphics = true; # Boot the vm in a window.
      diskSize = 1000; # Virtual machine disk size in MB.
    };
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
  environment.systemPackages = with pkgs; [
    git
    vim
  ];
  services.xserver.enable = true;
  
  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Required to install flatpak
  xdg.portal = {
    enable = true;
    config = {
      common = {
        default = [
          "gtk"
        ];
      };
    };
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      #      xdg-desktop-portal-kde
      #      xdg-desktop-portal-gtk
    ];
  };

  system.stateVersion = "23.11";
}
