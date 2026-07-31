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
* Wayland works through `qt6.qtwayland` and additional `LD_LIBRARY_PATH` /
  env handling on top of `wrapQtAppsHook` (see Troubleshooting).

## Troubleshooting

Hard-won notes from getting Happ working on a hardware Wayland session
(verified on phosh, Snapdragon 845 / Adreno 630, aarch64):

* **Window is black / SIGSEGV right after launch.** libxkbcommon can't find its
  keymap data and crashes during load (`xkbcommon: failed to add default include
  path /usr/share/X11/xkb` → `failed to create xkb context`). Fixed by setting
  `XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb` in `qtWrapperArgs`.

* **GUI renders black for minutes / is unstable, and the VPN drops with it.** The
  `.deb` bundles `libwayland-client.so.0.22`, but the system compositor + mesa use
  a newer one (e.g. 1.25). Two libwayland-client instances make
  `eglGetDisplay(wl_display)` fail (`qt.qpa.wayland: EGL not available` →
  `QRhiGles2: Failed to create context`), so QtQuick silently falls back to the
  **software** backend — which on a weak GPU is glacial and unstable, and because
  Happ's proxy core runs in-process, an unstable GUI drops the tunnel. Fix: put
  `pkgs.wayland` FIRST on `LD_LIBRARY_PATH` (shadows the bundled 1.22) plus
  `pkgs.libglvnd` + `/run/opengl-driver/lib` + `__EGL_VENDOR_LIBRARY_DIRS` so Qt
  gets **hardware** GL. All of this is now baked into `qtWrapperArgs`.
  Requires `hardware.graphics.enable = true` (populates `/run/opengl-driver`).

* **The icon uses the package's `Happ.desktop` → `bin/happ`** (the `wrapQtAppsHook`
  wrapper), so the env above must live in `qtWrapperArgs`, not in a hand-written
  `.desktop` you drop elsewhere (`/etc/xdg/applications` is not on `XDG_DATA_DIRS`
  and won't be used).

* **VPN "connects" then disconnects immediately.** Happ runs its **own** proxy
  core (xray/sing-box) bound to `127.0.0.1:10808`. If anything else already
  listens on that port — e.g. a `services.sing-box` placeholder — Happ's core
  can't bind it and the tunnel tears down at once. Don't occupy `:10808`.

## License

[GPL-3.0](LICENSE)

## Thanks

Inspired by the original NixOS module:
[MrShitFox/happ-nixos](https://github.com/MrShitFox/happ-nixos).

