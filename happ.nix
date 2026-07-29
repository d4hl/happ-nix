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

    # Если без этого всё работает — удалить.
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    (lib.makeLibraryPath (
      with pkgs;
      [
        libxkbcommon
        openssl
      ]
    ))
  ];

  meta = with lib; {
    description = "Happ proxy desktop client";
    homepage = "https://github.com/Happ-proxy/happ-desktop";
    platforms = platforms.linux;
    mainProgram = "happ";
  };
}
