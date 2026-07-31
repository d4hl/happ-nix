{ pkgs, lib }:

let
  arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
  sha256 = if pkgs.stdenv.hostPlatform.isAarch64
    then "19jay54wnj7ypqkhjmrb4s3lh09nwyy8c3yz7jr1vdhxmgfddlx4"
    else "1926zkpj59p1bc5h5asy78isyx1f1zs41bdi948gwyrqfw9cbnm7";
in
pkgs.stdenv.mkDerivation rec {
  pname = "happ-desktop";
  version = "3.3.6";

  src = pkgs.fetchurl {
    url = "https://github.com/Happ-proxy/happ-desktop/releases/download/${version}/Happ.linux.${arch}.deb";
    inherit sha256;
  };

  nativeBuildInputs = with pkgs; [
    autoPatchelfHook
    dpkg
    e2fsprogs
    qt6.qtbase
    qt6.wrapQtAppsHook
    stdenv.cc.cc
  ];

  buildInputs = with pkgs; [
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    dpkg -x "$src" root

    cp -r root/opt/happ $out/

    if [ -d root/usr/share ]; then
      mkdir -p $out/share
      cp -r root/usr/share/* $out/share/
    fi

    mkdir -p $out/bin

    ln -s $out/happ/bin/Happ $out/bin/happ
    ln -s $out/happ/bin/happd $out/bin/happd

    substituteInPlace \
      $out/share/applications/Happ.desktop \
      --replace-fail "/opt/happ/bin/Happ" "$out/bin/happ"

    runHook postInstall
  '';

  qtWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath (with pkgs; [ glib ]))

    "--set"
    "SSL_CERT_FILE"
    "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

    # libxkbcommon finds its keymap DATA via XKB_CONFIG_ROOT; without it the deb's
    # Qt build hits "xkbcommon: failed to add default include path /usr/share/X11/xkb"
    # -> "failed to create xkb context" -> SIGSEGV on load (window never appears).
    "--set"
    "XKB_CONFIG_ROOT"
    "${pkgs.xkeyboard_config}/share/X11/xkb"

    # GLVND finds the mesa EGL vendor via the NixOS driver ICD dir.
    "--set"
    "__EGL_VENDOR_LIBRARY_DIRS"
    "/run/opengl-driver/share/glvnd/egl_vendor.d"

    # LD_LIBRARY_PATH (needed — TLS + hardware GL):
    #  - openssl: else Qt's TLS backend is "cert-only" and the HTTPS subscription
    #    fetch fails.
    #  - wayland: the deb bundles libwayland-client 1.22, but mesa/the compositor
    #    use a newer one (e.g. 1.25). Two libwayland-client instances make
    #    eglGetDisplay(wl_display) fail -> "EGL not available" -> QtQuick falls back
    #    to the software backend, which on weak GPUs (sdm845/Adreno 630) takes
    #    minutes to draw, is unstable, and drags the in-process proxy core down with
    #    it. Putting pkgs.wayland on LD_LIBRARY_PATH shadows the bundled 1.22 so the
    #    single system libwayland is used, and eglGetDisplay succeeds.
    #  - libglvnd + /run/opengl-driver/lib: the GLVND libEGL.so.1 loader + the
    #    NixOS mesa driver tree -> hardware GL (Adreno) instead of llvmpipe.
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "${
      lib.makeLibraryPath (
        with pkgs;
        [
          wayland
          libglvnd
          libxkbcommon
          openssl
        ]
      )
    }:/run/opengl-driver/lib"
  ];

  meta = with lib; {
    description = "Happ proxy desktop client";
    homepage = "https://github.com/Happ-proxy/happ-desktop";
    platforms = platforms.linux;
    mainProgram = "happ";
  };
}
