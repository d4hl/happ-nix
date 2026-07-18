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

      system.activationScripts.happ-opt = lib.stringAfter [ "stdio" ] ''
        stamp=/opt/happ/.nix-store-path
        if [ "$(cat "$stamp" 2>/dev/null)" != "${cfg.package}" ]; then
          rm -rf /opt/happ
          mkdir -p /opt/happ
          cp -r ${cfg.package}/happ/. /opt/happ/
          chmod -R 0777 /opt/happ
          printf '%s' "${cfg.package}" > "$stamp"
        fi
      '';

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

          ExecStart = "/opt/happ/bin/happd";

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

