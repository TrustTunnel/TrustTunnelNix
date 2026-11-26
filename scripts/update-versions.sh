#!/usr/bin/env bash
# Bump both TrustTunnel packages to the latest stable upstream release.
#
#   scripts/update-versions.sh [--dry-run]
#
# The script first compares the latest upstream tags with the pinned
# versions. When both packages are current, it exits without downloading
# release assets or running nix-update.
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$script_dir")"
script_path="$script_dir/$(basename "${BASH_SOURCE[0]}")"
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

# The version check needs curl and jq. Use the flake's nixpkgs when the host
# lacks them.
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  exec nix shell --inputs-from . nixpkgs#curl nixpkgs#jq --command bash "$script_path" "$@"
fi

client_file="pkgs/trusttunnel-client.nix"
endpoint_file="pkgs/trusttunnel-endpoint.nix"

pinned_version() {
  sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$1" | head -n 1
}

github_get() {
  local url=$1
  local args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "$url"
}

latest_version() {
  github_get "https://api.github.com/repos/$1/releases/latest" \
    | jq -r '.tag_name' \
    | sed 's/^v//'
}

pinned_client="$(pinned_version "$client_file")"
pinned_endpoint="$(pinned_version "$endpoint_file")"
if [[ -z "$pinned_client" || -z "$pinned_endpoint" ]]; then
  echo "error: cannot read a pinned version from the package files" >&2
  exit 1
fi

latest_client="$(latest_version "TrustTunnel/TrustTunnelClient")"
latest_endpoint="$(latest_version "TrustTunnel/TrustTunnel")"

client_update=false
endpoint_update=false
if [[ "$latest_client" != "$pinned_client" ]]; then
  client_update=true
fi
if [[ "$latest_endpoint" != "$pinned_endpoint" ]]; then
  endpoint_update=true
fi

if [[ "$client_update" == false && "$endpoint_update" == false ]]; then
  echo "All packages are up to date (client ${pinned_client}, endpoint ${pinned_endpoint})."
  exit 0
fi

if [[ "$client_update" == true ]]; then
  echo "Client: ${pinned_client} -> ${latest_client}"
else
  echo "Client: ${pinned_client} is current."
fi
if [[ "$endpoint_update" == true ]]; then
  echo "Endpoint: ${pinned_endpoint} -> ${latest_endpoint}"
else
  echo "Endpoint: ${pinned_endpoint} is current."
fi

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

if [[ "$client_update" == true ]]; then
  # Provide curl, jq, and python3 from the flake's nixpkgs instead of the
  # runner's channel. Invoke the script with bash so its nix-shell shebang is
  # not used.
  nix shell --inputs-from . \
    nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#python3 \
    --command bash scripts/update-client.sh --version "$latest_client"
fi

if [[ "$endpoint_update" == true ]]; then
  # Keep the committed Cargo.lock and boring-v5.patch. Only the source changes.
  nix run --inputs-from . nixpkgs#nix-update -- \
    --flake --src-only --version "$latest_endpoint" trusttunnel-endpoint
fi

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
