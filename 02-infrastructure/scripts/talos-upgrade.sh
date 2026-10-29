#!/usr/bin/env bash
# Upgrades the running cluster to talos-versions.yaml
# Usage: talos-upgrade.sh <talos-versions.yaml>   (TALOSCONFIG and KUBECONFIG set)
set -euo pipefail

talos=$(yq -r '.talos' "$1")
k8s=$(yq -r '.kubernetes' "$1")

k() { kubectl --request-timeout=20s "$@"; }

t() {
  local ip=$1
  shift
  talosctl -e "$ip" -n "$ip" "$@"
}

older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }
oldest() { sort -V | head -n1; }

on_target() {
  [ "$(k get node "$1" -o jsonpath='{.status.nodeInfo.osImage}/{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "Talos ($talos)/True" ]
}

# Kubernetes moves one minor per upgrade and Talos is only tested between adjacent minors.
refuse_minor_skip() {
  local from to
  from=$(cut -d. -f2 <<<"$2")
  to=$(cut -d. -f2 <<<"$3")
  if ((to > from + 1)); then
    echo "::error::$1 $2 -> $3 skips a minor version; merge the intermediate minor first"
    exit 1
  fi
}

nodes=$(k get nodes -o json | jq -r '
  .items
  | sort_by(
      (if .metadata.labels | has("node-role.kubernetes.io/control-plane") then 0
       elif .metadata.labels.dedicated == "database" then 1
       else 2 end),
      .metadata.name)
  | .[]
  | [ .metadata.name,
      ([.status.addresses[] | select(.type == "InternalIP") | .address][0]),
      (.status.nodeInfo.osImage | capture("\\((?<v>[^)]+)\\)").v),
      (if .metadata.labels.dedicated == "database" then "false" else "true" end) ]
  | @tsv')
cp_ip=$(head -n1 <<<"$nodes" | cut -f2)
oldest_kubelet=$(k get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' |
  sed 's/^v//' | oldest)

refuse_minor_skip Talos "$(cut -f3 <<<"$nodes" | oldest)" "$talos"
refuse_minor_skip Kubernetes "$oldest_kubelet" "$k8s"

while IFS=$'\t' read -r name ip running drain <&3; do
  if ! older "$running" "$talos"; then
    continue
  fi

  schematic=$(t "$ip" get extensions -o json |
    jq -r 'select(.spec.metadata.name == "schematic") | .spec.metadata.version')
  [ -n "$schematic" ] || {
    echo "::error::$name reports no Image Factory schematic"
    exit 1
  }

  echo "::group::$name: Talos $running -> $talos"
  curl -fsS -o /dev/null -I --max-time 900 \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://factory.talos.dev/v2/installer/$schematic/manifests/$talos"
  talosctl -e "$cp_ip" -n "$ip" upgrade --image "factory.talos.dev/installer/$schematic:$talos" --drain="$drain" || {
    k uncordon "$name" || true
    echo "::error::$name: talosctl upgrade failed"
    exit 1
  }
  for _ in $(seq 120); do
    on_target "$name" && break
    sleep 10
  done
  on_target "$name" || {
    echo "::error::$name is not Ready on Talos $talos after 20 minutes ($(k get node "$name" -o jsonpath='{.status.nodeInfo.osImage}' 2>/dev/null))"
    exit 1
  }
  t "$cp_ip" health --wait-timeout 10m
  echo "::endgroup::"
done 3<<<"$nodes"

if older "$oldest_kubelet" "$k8s"; then
  echo "::group::Kubernetes $oldest_kubelet -> $k8s"
  t "$cp_ip" upgrade-k8s --to "$k8s"
  t "$cp_ip" health --wait-timeout 10m
  echo "::endgroup::"
fi
