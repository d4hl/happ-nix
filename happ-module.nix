{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkEnableOption mkOption types stringAfter;
  cfg = config.services.happ;
in
{
  options.services.happ = {
    enable = mkEnableOption "Happ proxy desktop client and background TUN daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./happ.nix { };
      defaultText = "pkgs.callPackage ./happ.nix { }";
      description = "The Happ package to use.";
    };

    tunInterface = mkOption {
      type = types.str;
      default = "tun0";
      description = ''
        Name of the TUN interface Happ brings up; it is added to the firewall's
        trusted interfaces so tunnelled traffic is not dropped.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Tools Happ and its helper scripts call from the system PATH.
    environment.systemPackages = [
      cfg.package
      pkgs.net-tools
      pkgs.lsb-release
    ];

    # HWID fix. Happ reads its hardware id from Qt's QSysInfo::machineUniqueId(),
    # which on Linux comes from /var/lib/dbus/machine-id. NixOS defaults to
    # dbus-broker, which (unlike the classic dbus-daemon) does not create that
    # file, so the id is empty and the client shows a blank HWID. Linking it to
    # the real /etc/machine-id fixes it.
    #
    # Note: keep happd (below) unsandboxed. systemd sandboxing (ProtectSystem,
    # PrivateTmp, ...) enables a mount namespace whose machine-id bind-mount fails
    # here with 226/NAMESPACE and breaks TUN mode.
    systemd.tmpfiles.rules = [
      "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
    ];

    # Firewall + TUN module for Happ's TUN mode.
    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ cfg.tunInterface ];
    boot.kernelModules = [ "tun" ];

    # Happ hard-codes /opt/happ for its binaries and writable runtime data, so we
    # materialise the immutable Nix store tree there. The copy runs only when the
    # package changes, keeping everyday rebuilds fast.
    system.activationScripts.happ-opt = stringAfter [ "stdio" ] ''
      stamp=/opt/happ/.nix-store-path
      if [ "$(cat "$stamp" 2>/dev/null)" != "${cfg.package}" ]; then
        rm -rf /opt/happ
        mkdir -p /opt/happ
        cp -r ${cfg.package}/happ/. /opt/happ/
        # Happ writes runtime data (routing, generated core configs) back into
        # /opt/happ, so it must stay writable by the desktop user.
        chmod -R 0777 /opt/happ
        printf '%s' "${cfg.package}" > "$stamp"
      fi
    '';

    # Privileged daemon that runs the TUN cores (sing-box / tun2proxy) as root.
    systemd.services.happd = {
      description = "Happ Process Control Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ iproute2 iptables procps net-tools ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        ExecStart = "/opt/happ/bin/happd";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "10s";
        KillMode = "mixed";
        KillSignal = "SIGTERM";
      };
    };
  };
}
