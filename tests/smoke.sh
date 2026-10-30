#!/usr/bin/env bash
set -euo pipefail

image=${1:?A locally loaded image is required}
version=${2:?The expected application version is required}
platform=${3:?The image platform is required}
container=
phase='starting the daemon with no replication jobs'
cleanup() {
    status=$?
    if [[ -n $container ]]; then
        if ((status != 0)); then
            printf 'zrepl smoke test failed while %s (exit status %s).\n' "$phase" "$status" >&2
            docker inspect --format '{{json .State}}' "$container" >&2 || true
            docker logs "$container" >&2 || true
        fi
        docker rm --force --volumes "$container" > /dev/null || true
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

container=$(docker create --pull=never --platform "$platform" --network none \
    --label "io.tuxcrate.smoke-test=${TUXCRATE_TEST_ID:-manual-zrepl-$$}" "$image")
docker cp tests/zrepl.yml "$container:/etc/zrepl/zrepl.yml"
docker start "$container" > /dev/null

phase='waiting for the daemon control interface'
deadline=$((SECONDS + 60))
while :; do
    if [[ $(docker inspect --format '{{.State.Running}}' "$container") != true ]]; then
        echo 'zrepl exited before becoming ready.' >&2
        exit 1
    fi
    if timeout 5 docker exec "$container" zrepl --config /etc/zrepl/zrepl.yml status --mode raw > /dev/null 2>&1; then
        break
    fi
    if ((SECONDS >= deadline)); then
        echo 'Timed out waiting for zrepl readiness.' >&2
        exit 1
    fi
    sleep 1
done

phase='checking the installed package version'
installed_version=$(docker exec "$container" dpkg-query --show --showformat='${Version}' zrepl)
if [[ $installed_version != "$version" ]]; then
    printf 'Expected zrepl package %s, got %s.\n' "$version" "$installed_version" >&2
    exit 1
fi

phase='checking graceful shutdown'
docker stop --time 30 "$container" > /dev/null
exit_code=$(docker wait "$container")
if [[ $exit_code != 0 ]]; then
    printf 'zrepl shutdown returned exit status %s.\n' "$exit_code" >&2
    exit 1
fi
