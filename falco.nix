{
  stdenv,
  cmake,
  fetchFromGitHub,
  uthash,
  zlib,
  elfutils,
  protobuf,
  jsoncpp,
  tbb,
  c-ares,
  openssl,
  curl,
  valijson,
  re2,
  grpc,
  linux,
  kernel ? linux,
  libbpf,
  clang,
  bpftool,
  nlohmann_json,
  yaml-cpp,
  httplib,
  cxxopts,
  cppcheck,
  writeText,
  localFalcoRulesContent ? "# Your custom rules!\n",
}:
let
  falco-libs = fetchFromGitHub {
    owner = "falcosecurity";
    repo = "libs";
    rev = "0.17.2";
    hash = "sha256-BTLXtdU7GjOJReaycHvXkSd2vtybnCn0rTR7OEsvaMQ=";
  };

  falco-rules = fetchFromGitHub {
    owner = "falcosecurity";
    repo = "rules";
    rev = "falco-rules-3.1.0";
    hash = "sha256-pqDQf2tqtGn/f1WXEN+cRb2SAci4lGqykS7Rty7swCY=";
  };

  local-falco-rules = writeText "falco_rules.local.yaml" localFalcoRulesContent;

  drv = stdenv.mkDerivation rec {
    pname = "falco";
    version = "0.38.1";
    src = fetchFromGitHub {
      owner = "falcosecurity";
      repo = pname;
      rev = version;
      hash = "sha256-TvAPL4c3BJm2BCXxZHKZClQyVFyiGcbuGqeYQhUHx3A=";
    };

    hardeningDisable = [ "zerocallusedregs" ];

    nativeBuildInputs = [
      cmake
      zlib
      elfutils
      libbpf
      clang
      bpftool
      protobuf
      c-ares
      openssl
      curl
      grpc
      re2
      valijson
      uthash
      jsoncpp
      tbb
      nlohmann_json
      yaml-cpp
      httplib
      cxxopts
      cppcheck
      falco-rules
    ];

    patches = [
      ./disable-falcoctl-build.patch
      ./allow-configure-falco-rules-directory.patch
    ];

    KERNELDIR = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";

    postUnpack = ''
      cp -r ${falco-libs} libs
      chmod -R +w libs

      substituteInPlace libs/userspace/libscap/libscap.pc.in libs/userspace/libsinsp/libsinsp.pc.in \
        --replace-fail "\''${prefix}/@CMAKE_INSTALL_LIBDIR@" "@CMAKE_INSTALL_FULL_LIBDIR@" \
        --replace-fail "\''${prefix}/@CMAKE_INSTALL_INCLUDEDIR@" "@CMAKE_INSTALL_FULL_INCLUDEDIR@"

      cmakeFlagsArray+=(
        "-DFALCOSECURITY_LIBS_SOURCE_DIR=$(pwd)/libs"
        "-DDRIVER_SOURCE_DIR=$(pwd)/libs/driver"
      );
    '';

    cmakeFlags = [
      "-DFALCO_VERSION=${version}"
      # Do not use bundled dependencies
      "-DUSE_BUNDLED_TBB=OFF"
      "-DUSE_BUNDLED_RE2=OFF"
      "-DUSE_BUNDLED_JSONCPP=OFF"
      "-DUSE_BUNDLED_UTHASH=OFF"
      "-DUSE_BUNDLED_DEPS=OFF"
      "-DUSE_BUNDLED_LIBBPF=OFF"
      "-DUSE_BUNDLED_VALIJSON=OFF"
      # Do not build FalcoCTL with falco
      "-DADD_FALCOCTL_DEPENDENCY=OFF"
      # Do not download the falco rules
      "-DFALCOSECURITY_RULES_FALCO_PATH=${falco-rules}/rules/falco_rules.yaml"
      "-DFALCOSECURITY_RULES_LOCAL_PATH=${local-falco-rules}"
    ];
  };
in
drv
