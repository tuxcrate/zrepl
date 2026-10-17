ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG APP_VERSION

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    : "${APP_VERSION:?APP_VERSION must be set}"; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get upgrade --yes --no-install-recommends; \
    apt-get install --yes --no-install-recommends ca-certificates curl gnupg; \
    install -d -m 0755 /usr/share/keyrings; \
    curl --fail --silent --show-error --location \
        https://zrepl.cschwarz.com/apt/apt-key.asc \
        | gpg --dearmor -o /usr/share/keyrings/zrepl-archive-keyring.gpg; \
    . /etc/os-release; \
    arch="$(dpkg --print-architecture)"; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/zrepl-archive-keyring.gpg] https://zrepl.cschwarz.com/apt/debian ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/zrepl.list; \
    echo "deb http://deb.debian.org/debian ${VERSION_CODENAME} contrib" \
        > /etc/apt/sources.list.d/contrib.list; \
    echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main contrib" \
        > /etc/apt/sources.list.d/backports.list; \
    printf 'Package: src:zfs-linux\nPin: release n=%s-backports\nPin-Priority: 990\n' "${VERSION_CODENAME}" \
        > /etc/apt/preferences.d/90_zfs; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
        "zrepl=${APP_VERSION}" zfsutils-linux; \
    test "$(dpkg-query --show --showformat='${Version}' zrepl)" = "${APP_VERSION}"; \
    install -d -m 0700 /var/run/zrepl; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    zrepl version --show client; \
    # Smoke tests must not require the host's ZFS kernel module.
    zfs --help; \
    zpool --help

WORKDIR /etc/zrepl

ENTRYPOINT ["/usr/bin/zrepl", "--config", "/etc/zrepl/zrepl.yml"]
CMD ["daemon"]
