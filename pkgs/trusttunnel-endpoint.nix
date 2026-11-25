{
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
  boringssl,
  cacert,
  python3,
  aws-lc,
  pkg-config,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "trusttunnel-endpoint";
  version = "1.3.1";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "TrustTunnel";
    repo = "TrustTunnel";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wn/ikm8ZlycFPvzToimJVW0t0AJMKurFKVtg9xoDIuA=";
  };

  # TrustTunnel 1.3.1 uses boring 4.22.0. This is compatible with the
  # boringssl shipped by nixos-25.11. The nixpkgs `boring-v5.patch` is only
  # needed with the newer boringssl in nixpkgs-unstable.
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./trusttunnel-endpoint-Cargo.lock;
  };

  # `importCargoLock` puts each crate directly under `cargoDepsCopy`. The
  # nixpkgs recipe uses `*/boring-sys-*` because `fetchCargoVendor` adds one
  # level. Link against the system boringssl instead of the static libraries.
  postPatch = ''
    substituteInPlace $cargoDepsCopy/boring-sys-*/build/main.rs $cargoDepsCopy/quiche-*/src/build.rs \
      --replace-fail "cargo:rustc-link-lib=static=crypto" "cargo:rustc-link-lib=dylib=crypto" \
      --replace-fail "cargo:rustc-link-lib=static=ssl" "cargo:rustc-link-lib=dylib=ssl"
  '';

  env = {
    BORING_BSSL_PATH = "${boringssl}";
    BORING_BSSL_INCLUDE_PATH = "${boringssl.dev}/include";
    # endpoint/build.rs falls back to "0.0.0-git" when the source has no .git.
    TRUSTTUNNEL_VERSION = finalAttrs.version;
  };

  postInstall = ''
    install -Dm644 LICENSE "$out/share/doc/trusttunnel-endpoint/LICENSE"
  '';

  nativeBuildInputs = [
    rustPlatform.bindgenHook
    pkg-config
  ];

  buildInputs = [
    boringssl
    aws-lc
  ];

  nativeCheckInputs = [
    cacert
    python3
  ];

  __darwinAllowLocalNetworking = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    version = finalAttrs.version;
    description = "Modern, fast and obfuscated VPN protocol - endpoint component";
    homepage = "https://github.com/TrustTunnel/TrustTunnel";
    changelog = "https://github.com/TrustTunnel/TrustTunnel/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    maintainers = [
      {
        name = "Ilya Zhirov";
        github = "i-zhirov";
      }
    ];
    mainProgram = "trusttunnel_endpoint";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
