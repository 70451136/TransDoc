#!/usr/bin/env bash
# Sourced helpers only. Never infer that missing containers mean disposable data.
assert_installation_owner() {
  local project="${COMPOSE_PROJECT_NAME:-transdoc-licensed}"
  [[ "$project" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo 'Invalid Compose project name.' >&2; return 1; }
  local containers owner container name volumes expected
  expected="$(pwd -P)"
  containers="$(docker ps -aq --filter "label=com.docker.compose.project=$project")" || return 1
  if [[ -n "$containers" ]]; then
    for container in $containers; do
      owner="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$container")" || return 1
      if [[ "$owner" != /* || "$(realpath -m -- "$owner")" != "$expected" ]]; then
        echo 'Existing Compose project belongs to a different or unknown directory. Continue from its original installation; no data changed.' >&2
        return 1
      fi
    done
    for name in installation.json compose.env node.env; do
      if [[ ! -f "config/$name" || -L "config/$name" ]]; then
        echo 'Existing services require the original complete private configuration. Restore config before continuing.' >&2
        return 1
      fi
    done
  else
    volumes="$(docker volume ls --filter "label=com.docker.compose.project=$project" --format '{{.Name}}')" || return 1
    if [[ -z "$volumes" ]]; then
      # Include legacy/manual volumes that lack Compose labels but use its exact names.
      volumes="$(docker volume ls --format '{{.Name}}')" || return 1
      volumes="$(printf '%s\n' "$volumes" | grep -E "^${project}_(database|cache|storage)$" || true)"
    fi
    if [[ -n "$volumes" ]]; then
      echo 'Orphan data volumes found. Restore and verify the original installation; refusing new credentials or automatic takeover.' >&2
      return 1
    fi
  fi
}
