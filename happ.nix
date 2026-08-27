{ pkgs, lib }:

pkgs.stdenv.mkDerivation rec {
  pname = "happ-desktop";
  version = "4.1.1";

  src = pkgs.fetchurl {
    url = "https://github.com/Happ-proxy/happ-desktop/releases/download/${version}/Happ.linux.x64.deb";
    sha256 = "sha256-LPP+BvEyU3JjyWiBo5HM5IMQruwHSLZ0GkNXsKYtzbg=";
  };

  nativeBuildInputs = with pkgs; [
    autoPatchelfHook
    dpkg
    e2fsprogs
    qt6.wrapQtAppsHook
    stdenv.cc.cc
  ];

  buildInputs = with pkgs; [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtsvg
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    dpkg -x "$src" root

    cp -r root/opt/happ $out/
    rm -rf $out/happ/lib

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

  meta = with lib; {
    description = "Happ proxy desktop client";
    homepage = "https://github.com/Happ-proxy/happ-desktop";
    platforms = platforms.linux;
    mainProgram = "happ";
  };
}
