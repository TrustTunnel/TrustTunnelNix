#!/usr/bin/env bash
# Bump both TrustTunnel packages to the latest stable upstream release.
#
#   scripts/update-versions.sh [--dry-run]
#
# The script changes only the package files:
#
#   - trusttunnel-client: scripts/update-client.sh fetches the release assets
#     and the source archive, computes their SRI hashes, and rewrites the pins.
#   - trusttunnel-endpoint: nix-update updates the source version and hash.
#     --src-only keeps the committed Cargo.lock, which boring-v5.patch
#     modifies. nix-update would otherwise replace it with the unpatched
#     upstream lock.
#
# The script does not validate or commit. Run `nix flake check` after it, then
# review and commit the changes. .github/workflows/update-versions.yml does
# this in CI.
#
# --dry-run prints the diff and restores the package files.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

dry_run=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      dry_run=true
      ;;
    -h|--help)
      echo "usage: $0 [--dry-run]"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      echo "usage: $0 [--dry-run]" >&2
      exit 2
      ;;
  esac
done

client_file="pkgs/trusttunnel-client.nix"
endpoint_file="pkgs/trusttunnel-endpoint.nix"

# A dry run must not discard local edits, so back up the two files instead of
# using `git checkout` to restore them.
backup_dir="$(mktemp -d)"
mkdir -p "$backup_dir/pkgs"
cp "$client_file" "$backup_dir/$client_file"
cp "$endpoint_file" "$backup_dir/$endpoint_file"

restore() {
  if [[ "$dry_run" == true ]]; then
    cp "$backup_dir/$client_file" "$client_file"
    cp "$backup_dir/$endpoint_file" "$endpoint_file"
  fi
  rm -rf "$backup_dir"
}
trap restore EXIT

# Provide curl, jq, and python3 from the flake's nixpkgs instead of the
# runner's channel. Invoke the script with bash so its nix-shell shebang is
# not used.
nix shell --inputs-from . \
  nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#python3 \
  --command bash scripts/update-client.sh

# Keep the committed Cargo.lock and boring-v5.patch. Only the source changes.
# --use-github-releases marks prereleases explicitly, as the Homebrew tap does.
nix run --inputs-from . nixpkgs#nix-update -- \
  --flake --src-only --use-github-releases trusttunnel-endpoint

if git diff --quiet -- "$client_file" "$endpoint_file"; then
  echo "All packages are up to date."
else
  echo "Package changes:"
  git --no-pager diff --stat -- "$client_file" "$endpoint_file"
  git --no-pager diff -- "$client_file" "$endpoint_file"
fi

if [[ "$dry_run" == true ]]; then
  echo "Dry run: the package files will be restored."
fi
