# Packaging notes

This page explains the build choices in the flake.

## The endpoint builds from source

The endpoint package builds TrustTunnel from source with Rust. The
package applies an upstream patch that moves boring from 4.22.0 to
boring 5 and quiche 0.30. boring 4.22.0 does not compile against the
boringssl in nixpkgs 26.05. The patch also makes boring-sys and quiche
link against the shared boringssl libraries.

## The client uses release binaries

The client package uses the upstream release binaries for Linux and
macOS. macOS uses one universal archive for both architectures.

The package also fetches the matching client source. The
`config-coverage` check compares the generated configuration keys with
that source. A client update without a matching source hash fails the
check.

## The flake pins nixpkgs

The flake pins `nixos-26.05`. The endpoint build depends on the
boringssl and Rust versions in that release. A different nixpkgs can
break the build.

Set `inputs.nixpkgs.follows = "nixpkgs"` to keep one nixpkgs in your
configuration.
