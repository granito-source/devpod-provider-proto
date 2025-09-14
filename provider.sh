#!/usr/bin/env bash

set -eu

cmd_find() {
    log "command: find: $1"

    local pvc
    pvc=$(pvc_find "$1")

    if [[ -z $pvc ]]; then
        log "PVC is not found: $1"

        return
    fi

    if [[ $(echo "$pvc" | jq -r '.config') == "null" ]]; then
        log "PVC does not have DevPod annotation: $1"

        return
    fi

    local pod
    pod=$(pod_find "$1")

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
    log "command: command: $1 $2 $3"

    if [[ $2 != "root" ]]; then
        kctl exec "$1" -c devpod -i -- su "$2" -c "$3"
    else
        kctl exec "$1" -c devpod -i -- sh -c "$3"
    fi
}

cmd_start() {
    log "command: start: $1"

    local pvc
    pvc=$(pvc_find "$1")

    if [[ -z $pvc ]]; then
        log "PVC is not found: $1"

        exit 1
    fi

    [[ -n $(pod_find "$1") ]] && pod_delete "$1"

    pod_create "$pvc"
    pod_wait $1 20
}

cmd_stop() {
    log "command: stop: $1"

    pod_delete "$1"
}

cmd_run() {
    log "command: run: $1"

    local pvc
    pvc=$(pvc_find "$1")

    if [[ -z $pvc ]]; then
        pvc=$(echo "$DEVCONTAINER_RUN_OPTIONS" | jq "{
            name: \"$1\",
            config: {
                WorkspaceID: \"$1\",
                Options: .
            }
        }")

        pvc_create "$pvc"
    fi

    [[ -n $(pod_find "$1") ]] && pod_delete "$1"

    pod_create "$pvc"
    pod_wait $1 20
}

cmd_delete() {
    log "command: delete: $1"

    pod_delete "$1"
    pvc_delete "$1"
}

cmd_target_architecture() {
    log "command: target-architecture"

    local arch
    arch=$(kctl run "$1-arch" --rm -iq --restart=Never --image="$HELPER_IMAGE" --command -- arch)

    if [[ $arch == "aarch64" ]]; then
        echo "arm64"
    else
        echo "$arch"
    fi
}

pvc_find() {
    log "pvc: find: $1"

    kctl get pvc "$1" --ignore-not-found -o json | jq '{
        name: .metadata.name,
        time: .metadata.creationTimestamp,
        config: (.metadata.annotations."devpod.sh/info" // "null") | fromjson
    }'
}

pvc_create() {
    log "pvc: create: $1"

    echo "$1" | jq "{
        apiVersion: \"v1\",
        kind: \"PersistentVolumeClaim\",
        metadata: {
            name,
            labels: {
                \"devpod.sh/created\": \"true\",
                \"devpod.sh/workspace-uid\": .config.Options.uid
            },
            annotations: {
                \"devpod.sh/info\": .config | tojson
            }
        },
        spec: {
            storageClassName: (if \"$STORAGE_CLASS\" == \"\" then null else \"$STORAGE_CLASS\" end),
            volumeMode: \"Filesystem\",
            accessModes: [\"$PVC_ACCESS_MODE\"],
            resources: {
                requests: {
                    storage: \"$DISK_SIZE\"
                }
            }
        }
    }" | kctl create -f - 1>&2
}

pvc_delete() {
    log "pvc: delete: $1"

    kctl delete pvc "$1" --ignore-not-found --grace-period=5 1>&2
}

pod_find() {
    log "pod: find: $1"

    kctl get pod "$1" --ignore-not-found -o json | jq '{
        phase: .status.phase,
        time: .status.startTime
    }'
}

pod_wait() {
    log "pod: wait: $1 $2"

    for (( i = 0; i < $2; i++ )); do
        [[ $(kctl get pod "$1" --ignore-not-found -o json |
            jq -r '.status.phase') == "Running" ]] && return
        sleep 1
    done

    log "pod: wait: $1: aborted after $2 attempts"
}

pod_create() {
    log "pod: create: $1"

    # XXX: check workspaceMount and workspaceVolumeMount

    echo "$1" | jq '.name as $name | {
        apiVersion: "v1",
        kind: "Pod",
        metadata: {
            name,
            labels: {
                "devpod.sh/created": "true",
                "devpod.sh/workspace-uid": .config.Options.uid
            }
        },
        spec: {
            restartPolicy: "Never",
            volumes: [
                {
                    name: "devpod",
                    persistentVolumeClaim: {
                        claimName: $name
                    }
                }
            ],
            containers: [
                {
                    name: "devpod",
                    image: .config.Options.image,
                    volumeMounts: ([
                        {
                            name: "devpod",
                            mountPath: .config.Options.workspaceMount.target,
                            subPath: "devpod/0"
                        }
                    ] + [
                        .config.Options.mounts[] | select(.type == "volume") | {
                            name: "devpod",
                            mountPath: .target,
                            subPath: ("devpod/" + .source)
                        }
                    ]),
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
    }' | kctl create -f - 1>&2
}

pod_delete() {
    log "pod: delete: $1"

    kctl delete pod "$1" --ignore-not-found --grace-period=10 1>&2
}

log() {
    echo "$@" 1>&2
}

kctl() {
    local -a cmd=("$KUBECTL_PATH")

    [[ -n $KUBERNETES_CONFIG ]] && cmd+=("--kubeconfig=$KUBERNETES_CONFIG")
    [[ -n $KUBERNETES_CONTEXT ]] && cmd+=("--context=$KUBERNETES_CONTEXT")

    cmd+=("--namespace=$KUBERNETES_NAMESPACE")

    "${cmd[@]}" "$@"
}

# main()

KUBECTL_PATH=${KUBECTL_PATH:-"kubectl"}
KUBERNETES_CONFIG=${KUBERNETES_CONFIG:-""}
KUBERNETES_CONTEXT=${KUBERNETES_CONTEXT:-""}
KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE:-"devpod"}
HELPER_IMAGE=${HELPER_IMAGE:-"alpine:latest"}
DEVCONTAINER_USER=${DEVCONTAINER_USER:-"root"}
DISK_SIZE=${DISK_SIZE:="10Gi"}
STORAGE_CLASS=${STORAGE_CLASS:-""}
PVC_ACCESS_MODE=${PVC_ACCESS_MODE:-"ReadWriteOnce"}
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
