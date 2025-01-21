{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  linuxPackages,
  kernel ? linuxPackages.kernel,
  installShellFiles,
  pkg-config,
  luajit,
  ncurses,
  perl,
  jsoncpp,
  openssl,
  curl,
  jq,
  gcc,
  elfutils,
  tbb,
  protobuf,
  grpc,
  yaml-cpp,
  nlohmann_json,
  re2,
  zstd,
  uthash,
  clang,
  libbpf,
  bpftools,
  httplib,
  cxxopts,
  valijson,
  writeText,
  localFalcoRulesContent ? "# Your custom rules!\n",
}:

let
  # Compare with https://github.com/falcosecurity/falco/blob/0.39.2/cmake/modules/falcosecurity-libs.cmake
  libsRev = "0.18.2";
  libsHash = "sha256-/JI74SrHdyDtikGsQTj7eLTSE+NWLhIZRHXYRjPlt2A=";

  # Compare with https://github.com/falcosecurity/falco/blob/0.39.2/cmake/modules/driver.cmake
  driver = fetchFromGitHub {
    owner = "falcosecurity";
    repo = "libs";
    rev = "7.3.0+driver";
    hash = "sha256-HZEp3yv15ZUNxtHYjPpB+8TTosHK6q8ATuFFFn5YaBo=";
  };

  falco-rules-version = "3.2.0";
  falco-rules = fetchFromGitHub {
    owner = "falcosecurity";
    repo = "rules";
    rev = "falco-rules-${falco-rules-version}";
    hash = "sha256-1UHce5QlQwdfVASf76O69cpN0PdBUYV9Z5YmypBzbNE=";
  };

  local-falco-rules = writeText "falco_rules.local.yaml" localFalcoRulesContent;

in
stdenv.mkDerivation (finalAttrs: {
  pname = "falco";
  version = "0.39.2";

  src = fetchFromGitHub {
    owner = "falcosecurity";
    repo = "falco";
    rev = finalAttrs.version;
    hash = "sha256-054Pb9j5hEdAgHr5rN0v0nc46ae2blFXeQUpRLKlDgY=";
  };

  nativeBuildInputs = [
    cmake
    perl
    installShellFiles
    pkg-config
  ];

  buildInputs = [
    luajit
    ncurses
    openssl
    curl
    jq
    gcc
    elfutils
    tbb
    re2
    protobuf
    grpc
    yaml-cpp
    jsoncpp
    nlohmann_json
    zstd
    uthash
    clang
    libbpf
    bpftools
    httplib
    cxxopts
    valijson
  ] ++ lib.optionals (kernel != null) kernel.moduleBuildDependencies;

  hardeningDisable = [
    "pic"
    "zerocallusedregs"
  ];

  postUnpack = ''
    cp -r ${
      fetchFromGitHub {
        owner = "falcosecurity";
        repo = "libs";
        rev = libsRev;
        hash = libsHash;
      }
    } libs
    chmod -R +w libs

    substituteInPlace libs/userspace/libscap/libscap.pc.in libs/userspace/libsinsp/libsinsp.pc.in \
      --replace-fail "\''${prefix}/@CMAKE_INSTALL_LIBDIR@" "@CMAKE_INSTALL_FULL_LIBDIR@" \
      --replace-fail "\''${prefix}/@CMAKE_INSTALL_INCLUDEDIR@" "@CMAKE_INSTALL_FULL_INCLUDEDIR@"

    cp -r ${driver} driver-src
    chmod -R +w driver-src
    # cp $\{driverKernel610MainC} driver-src/driver/main.c

    cmakeFlagsArray+=(
      "-DFALCOSECURITY_LIBS_SOURCE_DIR=$(pwd)/libs"
      "-DDRIVER_SOURCE_DIR=$(pwd)/driver-src/driver"
    )
  '';

  cmakeFlags = [
    "-DUSE_BUNDLED_DEPS=OFF"
    "-DFALCO_VERSION=${finalAttrs.version}"
    "-DUSE_BUNDLED_B64=OFF"
    "-DUSE_BUNDLED_TBB=OFF"
    "-DUSE_BUNDLED_RE2=OFF"
    "-DUSE_BUNDLED_JSONCPP=OFF"
    "-DUSE_BUNDLED_VALIJSON=OFF"
    "-DCREATE_TEST_TARGETS=OFF"
    # "-DVALIJSON_INCLUDE=${valijson}/include"
    "-DUTHASH_INCLUDE=${uthash}/include"
    "-DADD_FALCOCTL_DEPENDENCY=OFF"

    # Do not download the falco rules
    "-DFALCOSECURITY_RULES_FALCO_PATH=${falco-rules}/rules/falco_rules.yaml"
    "-DFALCOSECURITY_RULES_LOCAL_PATH=${local-falco-rules}"
  ] ++ lib.optional (kernel == null) "-DBUILD_DRIVER=OFF";

  env.NIX_CFLAGS_COMPILE =
    # fix compiler warnings been treated as errors
    "-Wno-error";

  preConfigure =
    ''
      if ! grep -q "${libsRev}" cmake/modules/falcosecurity-libs.cmake; then
        echo "falcosecurity-libs checksum needs to be updated!"
        exit 1
      fi
      cmakeFlagsArray+=(-DCMAKE_EXE_LINKER_FLAGS="-ltbb -lcurl -lzstd -labsl_synchronization")
    ''
    + lib.optionalString (kernel != null) ''
      export INSTALL_MOD_PATH="$out"
      export KERNELDIR="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    '';

  postInstall = lib.optionalString (kernel != null) ''
    make install_driver
    kernel_dev=${kernel.dev}
    kernel_dev=''${kernel_dev#${builtins.storeDir}/}
    kernel_dev=''${kernel_dev%%-linux*dev*}
    if test -f "$out/lib/modules/${kernel.modDirVersion}/extra/scap.ko"; then
        sed -i "s#$kernel_dev#................................#g" $out/lib/modules/${kernel.modDirVersion}/extra/scap.ko
    else
        for i in $out/lib/modules/${kernel.modDirVersion}/{extra,updates}/scap.ko.xz; do
          if test -f "$i"; then
            xz -d $i
            sed -i "s#$kernel_dev#................................#g" ''${i%.xz}
            xz -9 ''${i%.xz}
          fi
        done
    fi
  '';

  meta = {
    description = "A tracepoint-based system tracing tool for Linux (with clients for other OSes)";
    license = with lib.licenses; [
      asl20
      gpl2Only
      mit
    ];
    maintainers = with lib.maintainers; [ tembleking ];
    platforms = [ "x86_64-linux" ] ++ lib.platforms.darwin;
    broken =
      kernel != null && ((lib.versionOlder kernel.version "4.14") || kernel.isHardened || kernel.isZen);
    homepage = "https://falco.org";
    downloadPage = "https://github.com/falcosecurity/falco/releases";
  };
})
