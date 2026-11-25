{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation (
  finalAttrs:
  let
    # The source is used by checks/config-coverage.nix to validate the client
    # configuration schema against the pinned release.
    clientSrcHash = "sha256-1O5ztAydZaU31bhZS7+Mm+yspezRykl+/OinYVC+fT4=";

    sources = {
      x86_64-linux = {
        suffix = "linux-x86_64";
        hash = "sha256-medkuywID3pgxEG1Gtdfp+wA5sioCv42AwrzcgG6Mvc=";
      };
      aarch64-linux = {
        suffix = "linux-aarch64";
        hash = "sha256-g37GRSDVRs3456MnYUWJ9k3GxPMOQI43iN57+u8FtSs=";
      };
      x86_64-darwin = {
        suffix = "macos-universal";
        hash = "sha256-KJbdbg3e7Ws3nFp75ysmuhu8etgwGC68LR+ICWWSUYY=";
      };
      aarch64-darwin = {
        suffix = "macos-universal";
        hash = "sha256-KJbdbg3e7Ws3nFp75ysmuhu8etgwGC68LR+ICWWSUYY=";
      };
    };

    system = stdenvNoCC.hostPlatform.system;
    source = sources.${system};
  in
  {
    pname = "trusttunnel-client";
    version = "1.3.0";

    src = fetchurl {
      url = "https://github.com/TrustTunnel/TrustTunnelClient/releases/download/v${finalAttrs.version}/trusttunnel_client-v${finalAttrs.version}-${source.suffix}.tar.gz";
      hash = source.hash;
    };

    sourceRoot = "trusttunnel_client-v${finalAttrs.version}-${source.suffix}";

    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 trusttunnel_client "$out/bin/trusttunnel_client"
      install -Dm644 LICENSE "$out/share/doc/trusttunnel-client/LICENSE"

      runHook postInstall
    '';

    passthru = {
      inherit clientSrcHash;
      clientSrc = fetchFromGitHub {
        owner = "TrustTunnel";
        repo = "TrustTunnelClient";
        tag = "v${finalAttrs.version}";
        hash = clientSrcHash;
      };
      updateScript = ../scripts/update-client.sh;
    };

    meta = {
      version = finalAttrs.version;
      description = "Command-line client for the TrustTunnel VPN";
      homepage = "https://github.com/TrustTunnel/TrustTunnelClient";
      changelog = "https://github.com/TrustTunnel/TrustTunnelClient/blob/v${finalAttrs.version}/CHANGELOG.md";
      license = lib.licenses.asl20;
      maintainers = [
        {
          name = "Ilya Zhirov";
          github = "i-zhirov";
        }
      ];
      mainProgram = "trusttunnel_client";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
)
