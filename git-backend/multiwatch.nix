{
  fetchurl,
  glib,
  lib,
  libev,
  meson,
  ninja,
  pkg-config,
  stdenv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "multiwatch";
  version = "1.0.1";

  src = fetchurl {
    url = "https://download.lighttpd.net/multiwatch/releases-1.x/multiwatch-${finalAttrs.version}.tar.xz";
    hash = "sha256-6KaPLIb5njTIas9zJf5tGcgXWTXyUhMUVS3OY74i8WQ=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    glib
    libev
  ];

  meta = {
    description = "Fork and supervise multiple instances of a program";
    homepage = "https://redmine.lighttpd.net/projects/multiwatch";
    license = lib.licenses.mit;
    mainProgram = "multiwatch";
    platforms = lib.platforms.unix;
  };
})
