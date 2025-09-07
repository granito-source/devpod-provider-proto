#!/usr/bin/env bash

set -eu

cmd_find() {
    log "find: $1"

    local pvc
    local pod

    pvc=$(find_pvc "$1")
    pod=$(kctl get pod "$1" --ignore-not-found -o json |
        jq '{
            phase: .status.phase,
            time: .status.startTime
        }')

    if [[ -z $pvc ]]; then
        echo "null"

        return
    fi

    if [[ $(echo "$pvc" | jq -r '.phase') != "Bound" ]]; then
        echo "null"

        return
    fi

    if [[ $(echo "$pvc" | jq -r '.config') == "null" ]]; then
        echo "null"

        return
    fi

    if [[ -z $pod ]]; then
        pod='{"phase": "Dead"}'
    fi

    jq -n "{
        pvc: $pvc,
        pod: $pod
    } | {
        ID: .pvc.name,
        Created: .pvc.time,
        State: {
            Status: (if .pod.phase == \"Running\" then \"running\" else \"exited\" end),
            StartedAt: (.pod.time // .pvc.time)
        },
        Config: {
            Labels: .pvc.config.Options.labels | map(capture(\"^(?<key>[^=]+)=(?<value>.*)$\")) | from_entries
        }
    }"
}

cmd_command() {
    log "command: $1 $2 $3"

    if [[ $2 != "root" ]]; then
        kctl exec "$1" -c devpod -i -- su "$2" -c "$3"
    else
        kctl exec "$1" -c devpod -i -- sh -c "$3"
    fi
}

cmd_start() {
    log "start: $1"

    local pvc
    pvc=$(find_pvc "$1")

    if [[ -z $pvc ]]; then
        log "PVC is not found: $1"
        exit 1
    fi

    # check workspaceMount and workspaceVolumeMount

    # check and stop if already running

    echo "$pvc" | jq '.name as $name | {
        apiVersion: "v1",
        kind: "Pod",
        metadata: {
            name
        },
        spec: {
            restartPolicy: "Never",
            securityContext: {},
            volumes: [
                .config.Options.mounts[] | select(.type == "volume") | {
                    name: .source,
                    persistentVolumeClaim: {
                        claimName: $name
                    }
                }
            ],
            initContainers: [],
            containers: [
                {
                    name: "devpod",
                    image: .config.Options.image,
                    securityContext: {},
                    resources: {},
                    volumeMounts: [
                        .config.Options.mounts[] | select(.type == "volume") | {
                            name: .source,
                            mountPath: .target,
                            subPath: ("devpod/" + .source)
                        }
                    ],
                    command: [.config.Options.entrypoint],
                    args: .config.Options.cmd,
                    env: [
                        .config.Options.env | to_entries[] | {
                            name: .key,
                            value
                        }
                    ]
                }
            ]
        }
    }' | kctl create -f -
}

cmd_stop() {
    log "stop: $1"

    kctl delete pod "$1" --ignore-not-found --grace-period=10
}

cmd_run() {
    log "run: $1"
    # DEVCONTAINER_RUN_OPTIONS (json)
    # check and create pvc
    # check and delete pod
    # create pod
}

cmd_delete() {
    log "delete: $1"

    kctl delete pod "$1" --ignore-not-found --grace-period=10
    kctl delete pvc "$1" --ignore-not-found --grace-period=5
}

cmd_target_architecture() {
    log "target-architecture"

    local arch
    arch=$(kctl run "$1-arch" --rm -iq --restart=Never --image="$HELPER_IMAGE" --command -- arch)

    if [[ $arch == "aarch64" ]]; then
        echo "arm64"
    else
        echo "$arch"
    fi
}

find_pvc() {
    kctl get pvc "$1" --ignore-not-found -o json |
        jq '{
            name: .metadata.name,
            phase: .status.phase,
            time: .metadata.creationTimestamp,
            config: (.metadata.annotations."devpod.sh/info" // "null") | fromjson
        }'
}

log() {
    echo "$@" 1>&2
}

kctl() {
    $KUBECTL_PATH --namespace "$KUBERNETES_NAMESPACE" "$@"
}

KUBECTL_PATH=${KUBECTL_PATH:-kubectl}
KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE:-"devpod"}
HELPER_IMAGE=${HELPER_IMAGE:-"alpine:latest"}
DEVCONTAINER_USER=${DEVCONTAINER_USER:-"root"}
workspace="devpod-$DEVCONTAINER_ID"

case "$1" in
    find)
        cmd_find "$workspace"
        ;;
    command)
        cmd_command "$workspace" "$DEVCONTAINER_USER" "$DEVCONTAINER_COMMAND"
        ;;
    start)
        cmd_start "$workspace"
        ;;
    stop)
        cmd_stop "$workspace"
        ;;
    run)
        cmd_run "$workspace"
        ;;
    delete)
        cmd_delete "$workspace"
        ;;
    target-architecture)
        cmd_target_architecture "$workspace"
        ;;
    *)
        log "unknown command: $1"
        exit 1
        ;;
esac
