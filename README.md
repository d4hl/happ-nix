# happ-nix

> Run the [Happ](https://github.com/Happ-proxy/happ-desktop) proxy client on NixOS — packaged properly, with a working HWID.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-x86__64--linux-success)

Happ ships as a prebuilt Debian package that assumes a regular FHS layout and a
writable `/opt/happ` — neither of which exists on NixOS. This flake repackages it
for the Nix store and wires up everything needed to run it cleanly, including the
**HWID fix** the plain `.deb` can't manage on a modern NixOS.

## Usage

### Run directly

```bash
nix run github:MrShitFox/happ-nix
```

### Install as a system package

```nix
# flake.nix
{
  inputs.happ-nix.url = "github:MrShitFox/happ-nix";

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

### Via overlay

```nix
nixpkgs.overlays = [ happ-nix.overlays.default ];
```

Then `pkgs.happ` is available everywhere.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `programs.happ.enable` | `false` | Enable the Happ client and the `happd` daemon. |
| `programs.happ.package` | `happ` | Override the Happ package. |
| `programs.happ.tunMode.interfaceName` | `"tun0"` | TUN device trusted by the firewall. |

## The HWID fix

Happ derives its hardware id from Qt's `machineUniqueId()`, which on Linux reads
`/var/lib/dbus/machine-id`. NixOS defaults to **dbus-broker**, and — unlike the
classic dbus-daemon — it doesn't create that file, so the id comes back empty and
the client shows a blank HWID. The module links it to the real machine id:

```nix
systemd.tmpfiles.rules = [ "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id" ];
```

## Notes

- Protocols: VLESS, VMess, Trojan, Shadowsocks over TUN. Hysteria2 is not supported.
- Happ is a closed-source but freely redistributable binary; the package leaves its
  license unset, so `allowUnfree` is not required.
- Unofficial community flake — not affiliated with the Happ project.

## License

[GPL-3.0](LICENSE) — see the LICENSE file.