{
  pkgs,
  lib,
}:
pkgs.stdenv.mkDerivation rec {
  pname = "happ-desktop";
  version = "2.18.3";

  src = pkgs.fetchurl {
    url = "https://github.com/Happ-proxy/happ-desktop/releases/download/${version}/Happ.linux.x64.deb";
    sha256 = "x2G4RCroEWT/FpjjXrCncVoYhkb5zJ0Ckwd10sC5QxQ=";
  };

  nativeBuildInputs = with pkgs; [
    dpkg
    autoPatchelfHook
    makeWrapper
    qt6.wrapQtAppsHook
  ];

  buildInputs = with pkgs; [
    stdenv.cc.cc.lib
    glib
    dbus
    libGL
    libX11
    libSM
    libICE
    libXext
    libXi
    libXtst
    e2fsprogs
    fontconfig
    freetype
    libgpg-error
    qt6.qtwayland
    openssl
    # Wayland/graphics deps — Happ uses Qt with the wayland platform plugin
    wayland
    libxkbcommon
    mesa
    libdrm
    vulkan-loader
    libxcb
    libxshmfence
    pulseaudio
  ];

  # ponytail: wrapQtAppsHook (postFixup) would overwrite manual wrapProgram below,
  # losing LD_LIBRARY_PATH for Wayland/EGL libs Qt loads via dlopen.
  # Handle everything manually in installPhase.
  dontWrapQtApps = true;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/happ $out/share/applications $out/bin

    dpkg -x $src .
    cp -r opt/happ/* $out/happ/
    [ -d usr/share ] && cp -r usr/share/* $out/share/

    for exe in Happ happd; do
      wrapProgram $out/happ/bin/$exe \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtwayland}/lib/qt-6/plugins" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtsvg}/lib/qt-6/plugins" \
        --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtdeclarative}/lib/qt-6/plugins" \
        --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml" \
        --prefix NIXPKGS_QT6_QML_IMPORT_PATH : "${pkgs.qt6.qtwayland}/lib/qt-6/qml" \
        --prefix LD_LIBRARY_PATH : "${
          lib.makeLibraryPath (
            with pkgs;
            [
              wayland
              libxkbcommon
              mesa
              libdrm
              vulkan-loader
              libxcb
              libxshmfence
              pulseaudio
              libGL
              openssl
            ]
          )
        }" \
        --prefix PATH : "${
          lib.makeBinPath (
            with pkgs;
            [
              coreutils
              lsb-release
              net-tools
              iproute2
              iptables
              procps
            ]
          )
        }" \
        --set SSL_CERT_FILE "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    done

    ln -s $out/happ/bin/Happ $out/bin/happ
    ln -s $out/happ/bin/happd $out/bin/happd

    substituteInPlace $out/share/applications/Happ.desktop --replace-fail "/opt/happ/bin/Happ" "$out/bin/happ"

    runHook postInstall
  '';

  meta = {
    description = "Happ proxy desktop client (VLESS/VMess/Trojan/Shadowsocks) with a TUN daemon";
    homepage = "https://github.com/Happ-proxy/happ-desktop";
    platforms = [ "x86_64-linux" ];
    mainProgram = "happ";
  };
}
