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

  disable-falcoctl-build-patch = writeText "disable-falcoctl-build-patch" ''
    diff --git a/cmake/modules/falcoctl.cmake b/cmake/modules/falcoctl.cmake
    index f462f552..f9ba3cf6 100644
    --- a/cmake/modules/falcoctl.cmake
    +++ b/cmake/modules/falcoctl.cmake
    @@ -14,10 +14,15 @@

     include(ExternalProject)

    +option(ADD_FALCOCTL_DEPENDENCY "Add falcoctl dependency while building falco" ON)
    +
    +if(ADD_FALCOCTL_DEPENDENCY)
     string(TOLOWER ''${CMAKE_HOST_SYSTEM_NAME} FALCOCTL_SYSTEM_NAME)

     set(FALCOCTL_VERSION "0.8.0")

    +message(STATUS "Building with falcoctl ''${FALCOCTL_VERSION}")
    +
     if(''${CMAKE_HOST_SYSTEM_PROCESSOR} STREQUAL "x86_64")
         set(FALCOCTL_SYSTEM_PROC_GO "amd64")
         set(FALCOCTL_HASH "7b763bfaf38faf582840af22750dca7150d03958a5dc47f6118748713d661589")
    @@ -36,3 +41,6 @@ ExternalProject_Add(

     install(PROGRAMS "''${PROJECT_BINARY_DIR}/falcoctl-prefix/src/falcoctl/falcoctl" DESTINATION "''${FALCO_BIN_DIR}" COMPONENT "''${FALCO_COMPONENT_NAME}")
     install(DIRECTORY DESTINATION "''${FALCO_ABSOLUTE_SHARE_DIR}/plugins" COMPONENT "''${FALCO_COMPONENT_NAME}")
    +else()
    +    message(STATUS "Won't build with falcoctl")
    +endif()
  '';

  allow-configure-falco-rules-dir = writeText "allow-configure-falco-rules-dir" ''
    diff --git a/cmake/modules/rules.cmake b/cmake/modules/rules.cmake
    index f62032ae..81a42946 100644
    --- a/cmake/modules/rules.cmake
    +++ b/cmake/modules/rules.cmake
    @@ -15,6 +15,7 @@
     include(GNUInstallDirs)
     include(ExternalProject)

    +if(NOT DEFINED FALCOSECURITY_RULES_FALCO_PATH)
     # falco_rules.yaml
     set(FALCOSECURITY_RULES_FALCO_VERSION "falco-rules-3.1.0")
     set(FALCOSECURITY_RULES_FALCO_CHECKSUM "SHA256=3b617920c0b66128627613e591a954eb9572747a4c287bc13b53b38786250162")
    @@ -28,10 +29,13 @@ ExternalProject_Add(
       INSTALL_COMMAND ""
       TEST_COMMAND ""
     )
    +endif()

    +if(NOT DEFINED FALCOSECURITY_RULES_LOCAL_PATH)
     # falco_rules.local.yaml
     set(FALCOSECURITY_RULES_LOCAL_PATH "''${PROJECT_BINARY_DIR}/falcosecurity-rules-local-prefix/falco_rules.local.yaml")
     file(WRITE "''${FALCOSECURITY_RULES_LOCAL_PATH}" "# Your custom rules!\n")
    +endif()

     if(NOT DEFINED FALCO_ETC_DIR)
     	set(FALCO_ETC_DIR "''${CMAKE_INSTALL_FULL_SYSCONFDIR}/falco")
  '';

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
      disable-falcoctl-build-patch
      allow-configure-falco-rules-dir
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
