# happ-nix

> A Nix wrapper for [Happ](https://github.com/Happ-proxy/happ-desktop) — a proxy client
> (VLESS/VMess/Trojan/Shadowsocks) with a TUN daemon.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Built from the official `.deb` package, unpacked into the Nix store, with
**working HWID support** on modern NixOS (dbus-broker).

## Quick start

```bash
# Run GUI directly
nix run github:DaHL-gh/happ-nix#happ

# Or use the default package
nix run github:DaHL-gh/happ-nix
```

## Flake outputs

| Output                                   | Description                          |
| ---------------------------------------- | ------------------------------------ |
| `packages.<system>.happ`                 | Happ package with Happ GUI and happd |
| `packages.<system>.default`              | Same as above                        |
| `apps.<system>.default`                  | Launches the Happ GUI                |
| `overlays.default`                       | Overlay providing `pkgs.happ`        |
| `nixosModules.default`                   | NixOS module with TUN daemon support |

## Installing on NixOS

```nix
{
  inputs.happ-nix.url = "github:DaHL-gh/happ-nix";

  outputs = { nixpkgs, happ-nix, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      modules = [
        happ-nix.nixosModules.default
        { programs.happ.enable = true; }
      ];
    };
  };
}
```

### Module options

| Option                         | Default | Description                              |
| ------------------------------ | ------- | ---------------------------------------- |
| `programs.happ.enable`         | `false` | Enables Happ GUI and happd               |
| `programs.happ.package`        | `happ`  | Custom Happ package                      |
| `programs.happ.tunMode.enable` | `false` | Enables TUN mode and the systemd service |

## TUN mode configuration

```nix
{
  programs.happ = {
    enable = true;
    tunMode.enable = true;
  };
}
```

Enables:

* `happd` systemd service (running as root)
* `/var/lib/dbus/machine-id` → `/etc/machine-id` symlink (HWID fix)
* `networking.firewall.checkReversePath = "loose"`
* `networking.firewall.trustedInterfaces = [ "tun0" ]`
* `tun` kernel module

## Overlay only

```nix
nixpkgs.overlays = [ happ-nix.overlays.default ];
```

## HWID fix

Happ retrieves its HWID using Qt's `machineUniqueId()`, which reads
`/var/lib/dbus/machine-id`.

On NixOS with dbus-broker this file may not exist, causing an empty HWID.

The module fixes this by creating a symlink:

```nix
systemd.tmpfiles.rules = [
  "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
];
```

## Notes

* Supported on `x86_64-linux` and `aarch64-linux`.
* The binary is proprietary but freely redistributable — `allowUnfree` is not required.
* Hysteria2 is not supported by the client.
* Wayland works through `qt6.qtwayland` and additional `LD_LIBRARY_PATH` handling
  on top of `wrapQtAppsHook`.

## License

[GPL-3.0](LICENSE)

## Thanks

Inspired by the original NixOS module:
[MrShitFox/happ-nixos](https://github.com/MrShitFox/happ-nixos).

