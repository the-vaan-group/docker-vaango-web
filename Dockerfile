#### MAIN
FROM debian:trixie-20260112 AS main

ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=development \
    SHELL=/bin/bash \
    TMP_DIR=/mnt/tmp \
    WORKDIR=/app

RUN echo 'Installing build dependencies' \
    && set -ex \
    && apt-get update \
    && apt-get --assume-yes --no-install-recommends install \
        ca-certificates \
        curl \
        fd-find \
        gnupg \
        jq \
        moreutils \
        parallel \
        tini \
        unzip \
    && echo 'Cleaning up' \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt \
    && echo 'Smoke test' \
    && gpg --version \
    && echo 'DONE'

RUN echo 'Installing Fish shell' \
  && set -ex \
  && FISH_VERSION='4.3.3-2' \
  && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='amd64';; \
    arm64) ARCH='arm64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  && curl -fsSLO --compressed "https://download.opensuse.org/repositories/shells:/fish:/release:/4/Debian_13/${ARCH}/fish_${FISH_VERSION}_${ARCH}.deb" \
  && apt-get update \
  && apt-get --assume-yes --no-install-recommends install "./fish_${FISH_VERSION}_${ARCH}.deb" \
  && echo 'Cleaning up' \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /var/cache/apt \
  && echo 'Smoke test' \
  && fish --version \
  && echo 'DONE'

RUN echo "Installing node" \
  && NODE_VERSION='24.13.0' \
  && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    arm64) ARCH='arm64';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  # use pre-existing gpg directory, see https://github.com/nodejs/docker-node/pull/1895#issuecomment-1550389150
  && export GNUPGHOME="$(mktemp -d)" \
  # gpg keys listed at https://github.com/nodejs/node#release-keys
  && set -ex \
  && for key in \
    5BE8A3F6C8A5C01D106C0AD820B1A390B168D356 \
    DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
    CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
    C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
    108F52B48DB57BB0CC439B2997B01419BD92F80A \
    A363A499291CBBC940DD62E41F10027AF002F8B0 \
  ; do \
      { gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" && gpg --batch --fingerprint "$key"; } || \
      { gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" && gpg --batch --fingerprint "$key"; } ; \
  done \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && gpgconf --kill all \
  && rm -rf "$GNUPGHOME" \
  && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  # smoke tests
  && node --version \
  && npm --version \
  && echo 'Done'

ENV PATH="${WORKDIR}/devops/bin:${WORKDIR}/bin:${WORKDIR}/node_modules/.bin:${PATH}"

WORKDIR ${WORKDIR}

ENV npm_config_cache="${TMP_DIR}/npm-cache" \
    npm_config_store_dir="${TMP_DIR}/pnpm-store"

RUN echo "Installing pnpm" \
    && PNPM_VERSION='10.28.1' \
    && npm install -g "pnpm@${PNPM_VERSION}" \
    && pnpm --version \
    && echo 'Done'

RUN echo "Installing development tools" \
    && echo "====================" \
    && echo "Installing Bun" \
    && echo 'Note: we have to use baseline version for VirtualBox because of missing AVX2 support' \
    && BUN_VERSION='1.3.8' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x64-baseline';; \
      arm64) ARCH='aarch64';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSLO --compressed "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${ARCH}.zip" \
    && curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt" | grep 'linux' | grep "${ARCH}.zip" > bunsums \
    && sha256sum --check bunsums --status \
    && unzip "bun-linux-${ARCH}.zip" \
    && cp -fv "bun-linux-${ARCH}/bun" /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && echo "Smoke test" \
    && bun --version \
    && echo "Cleaning up" \
    && rm -rf ./bun* \
    && echo "===================" \
    && echo "Installing babashka" \
    && BABASHKA_VERSION='1.12.214' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='amd64';; \
      arm64) ARCH='aarch64';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSL --compressed --output bb.tar.gz \
      "https://github.com/babashka/babashka/releases/download/v${BABASHKA_VERSION}/babashka-${BABASHKA_VERSION}-linux-${ARCH}-static.tar.gz" \
    && curl -fsSL --output bb.tar.gz.sha256 \
      "https://github.com/babashka/babashka/releases/download/v${BABASHKA_VERSION}/babashka-${BABASHKA_VERSION}-linux-${ARCH}-static.tar.gz.sha256" \
    && echo "$(cat bb.tar.gz.sha256) bb.tar.gz" | sha256sum --check --status \
    && tar -xf ./bb.tar.gz \
    && cp -fv bb /usr/local/bin \
    && chmod +x /usr/local/bin/bb \
    && echo "Cleaning up" \
    && rm -rf ./bb* \
    && echo "==================" \
    && echo "Installing ripgrep" \
    && RIPGREP_VERSION='14.1.1' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x86_64-unknown-linux-musl';; \
      arm64) ARCH='aarch64-unknown-linux-gnu';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSL --compressed --output ripgrep.tar.gz \
      "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${ARCH}.tar.gz" \
    && curl -fsSL --output 'ripgrep.tar.gz.sha256' \
      "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${ARCH}.tar.gz.sha256" \
    && echo "$(cat ripgrep.tar.gz.sha256 | awk '{print $1}') ripgrep.tar.gz" | sha256sum --check --status \
    && tar -xf ./ripgrep.tar.gz \
    && cp -fv ./ripgrep-${RIPGREP_VERSION}-${ARCH}/rg /usr/local/bin \
    && chmod +x /usr/local/bin/rg \
    && echo "Cleaning up" \
    && rm -rf ./ripgrep* \
    && echo "====================" \
    && echo "Installing watchexec" \
    && WATCHEXEC_VERSION='1.23.0' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x86_64-unknown-linux-musl';; \
      arm64) ARCH='aarch64-unknown-linux-musl';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSLO --compressed "https://github.com/watchexec/watchexec/releases/download/v${WATCHEXEC_VERSION}/watchexec-${WATCHEXEC_VERSION}-${ARCH}.tar.xz" \
    && curl -fsSL "https://github.com/watchexec/watchexec/releases/download/v${WATCHEXEC_VERSION}/SHA512SUMS" | grep $ARCH | grep '.tar.xz' > watchexecsums \
    && sha512sum --check watchexecsums --status \
    && tar -xJf "./watchexec-${WATCHEXEC_VERSION}-${ARCH}.tar.xz" \
    && cp -fv "./watchexec-${WATCHEXEC_VERSION}-${ARCH}/watchexec" /usr/local/bin \
    && chmod +x /usr/local/bin/watchexec \
    && echo "Cleaning up" \
    && rm -rf ./watchexec* \
    && echo "===================" \
    && echo "Installing Hivemind" \
    && HIVEMIND_VERSION='1.0.6' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='amd64';; \
      arm64) ARCH='arm64';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSLO --compressed "https://github.com/DarthSim/hivemind/releases/download/v${HIVEMIND_VERSION}/hivemind-v${HIVEMIND_VERSION}-linux-${ARCH}.gz" \
    && gunzip "./hivemind-v${HIVEMIND_VERSION}-linux-${ARCH}.gz" \
    && cp -fv "./hivemind-v${HIVEMIND_VERSION}-linux-${ARCH}" /usr/local/bin/hivemind \
    && chmod +x /usr/local/bin/hivemind \
    && echo "Cleaning up" \
    && rm -rf ./hivemind* \
    && echo '==============================' \
    && echo 'Installing Starship prompt' \
    && STARSHIP_VERSION='1.23.0' \
    && ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x86_64';; \
      arm64) ARCH='aarch64';; \
      *) echo "unsupported architecture -- ${dpkgArch##*-}"; exit 1 ;; \
    esac \
    && set -ex \
    && cd $TMP_DIR \
    && curl -fsSL --compressed --output starship.tar.gz \
      "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${ARCH}-unknown-linux-musl.tar.gz" \
    && curl -fsSL --output starship.tar.gz.sha256 \
      "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${ARCH}-unknown-linux-musl.tar.gz.sha256" \
    && echo "$(cat starship.tar.gz.sha256) starship.tar.gz" | sha256sum --check --status \
    && tar -xf ./starship.tar.gz \
    && cp -fv starship /usr/local/bin \
    && chmod +x /usr/local/bin/starship \
    && echo "Cleaning up" \
    && rm -rf ./starship* \
    && echo "Smoke test" \
    && starship --version \
    && echo 'DONE'

