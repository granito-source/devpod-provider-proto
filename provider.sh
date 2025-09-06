#!/usr/bin/env bash

set -eux

log() {
    echo "$@" 1>&2
}

find_pod() {
    log "find: $DEVCONTAINER_ID"

    local pvc
    local pod

    pvc=$($KUBECTL_PATH --namespace "$KUBERNETES_NAMESPACE" get pvc "$name" --ignore-not-found -o json | jq -r '.status.phase')
    # ID <- $name
    # Created <- .metadata.creationTimestamp: "2025-09-02T12:12:52Z"
    pod=$($KUBECTL_PATH --namespace "$KUBERNETES_NAMESPACE" get pod "$name" --ignore-not-found -o json | jq -r '.status.phase')
    # State <- {
    #   Status <- "exited" | "running"
    #   StartedAt <-.status.startTime: "2025-08-24T18:55:45Z" | .metadata.creationTimestamp: "2025-09-02T12:12:52Z"
    # }
    # Config <- {
    #   Labels <- .metadata.labels
    #   WorkingDir <-
    # }

    log "pvc: $pvc, pod: $pod"

    echo "null"
}

do_command() {
    log "command: $DEVCONTAINER_ID"
    # DEVCONTAINER_USER
    # DEVCONTAINER_COMMAND
    # exec -c devpod
}

do_start() {
    log "start: $DEVCONTAINER_ID"
    # create pod
}

do_stop() {
    log "stop: $DEVCONTAINER_ID"
    # delete pod
}

do_run() {
    log "run: $DEVCONTAINER_ID"
    # DEVCONTAINER_RUN_OPTIONS (json)
}

do_delete() {
    log "delete: $DEVCONTAINER_ID"
    # delete pod
    # delete pvc
}

get_arch() {
    log "target-architecture: $DEVCONTAINER_ID"

    local arch
    arch=$($KUBECTL_PATH run "${name}-arch" --rm -iq --restart=Never --image="$HELPER_IMAGE" --command -- arch)

    if [[ $arch == "aarch64" ]]; then
        echo "arm64"
    else
        echo "$arch"
    fi
}

KUBECTL_PATH=${KUBECTL_PATH:-kubectl}
KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE:-"devpod"}
HELPER_IMAGE=${HELPER_IMAGE:-"alpine:latest"}
name="devpod-$DEVCONTAINER_ID"

case "$1" in
    find)
        find_pod
        ;;
    command)
        do_command
        ;;
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    run)
        do_run
        ;;
    delete)
        do_delete
        ;;
    target-architecture)
        get_arch
        ;;
    *)
        log "unknown command: $1"
        exit 1
        ;;
esac

# type ContainerDetails struct {
# 	ID      string                 `json:"ID,omitempty"`
# 	Created string                 `json:"Created,omitempty"`
# 	State   ContainerDetailsState  `json:"State,omitempty"`
# 	Config  ContainerDetailsConfig `json:"Config,omitempty"`
# }

# 21:59:23 info PROVIDER_ID=k8s
# 21:59:23 info WORKSPACE_PROVIDER=k8s
# 21:59:23 info KUBERNETES_CONFIG=
# 21:59:23 info NODE_SELECTOR=
# 21:59:23 info INACTIVITY_TIMEOUT=
# 21:59:23 info WORKSPACE_CONTEXT=default
# 21:59:23 info WORKSPACE_ID=xxx
# 21:59:23 info WORKSPACE_VOLUME_MOUNT=
# 21:59:23 info MACHINE_CONTEXT=default
# 21:59:23 info PROVIDER_CONTEXT=default
# 21:59:23 info KUBERNETES_NAMESPACE=yashkov
# 21:59:23 info HELPER_RESOURCES=
# 21:59:23 info DANGEROUSLY_OVERRIDE_IMAGE=
# 21:59:23 info STRICT_SECURITY=false
# 21:59:23 info DOCKERLESS_IMAGE=
# 21:59:23 info DOCKERLESS_DISABLED=false
# 21:59:23 info STORAGE_CLASS=
# 21:59:23 info DISK_SIZE=10Gi
# 21:59:23 info PVC_ACCESS_MODE=
# 21:59:23 info DEVPOD_ARCH=arm64
# 21:59:23 info DEVPOD_OS=darwin
# 21:59:23 info DEVPOD_DEBUG=true
# 21:59:23 info DEVPOD_LOG_LEVEL=debug
