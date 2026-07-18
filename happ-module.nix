{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.happ;
in
{
  options.programs.happ = {
    enable = lib.mkEnableOption "Happ desktop client";

    package = lib.mkPackageOption pkgs "happ" { };

    tunMode.enable = lib.mkEnableOption "Happ TUN mode";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    })
    (lib.mkIf (cfg.enable && cfg.tunMode.enable) {
      # HWID fix
      systemd.tmpfiles.rules = [
        "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
      ];

      networking.firewall.checkReversePath = "loose";
      networking.firewall.trustedInterfaces = [ "tun0" ];
      boot.kernelModules = [ "tun" ];

      systemd.services.happd = {
        description = "Happ Process Control Daemon";

        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        path = with pkgs; [
          iproute2
          iptables
          procps
          net-tools
        ];

        serviceConfig = {
          Type = "simple";
          User = "root";
          Group = "root";

          ExecStart = "${cfg.package}/bin/happd";

          Restart = "on-failure";
          RestartSec = "5s";

          TimeoutStopSec = "10s";
          KillMode = "mixed";
          KillSignal = "SIGTERM";
        };
      };
    })
  ];
}

