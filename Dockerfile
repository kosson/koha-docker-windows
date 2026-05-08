FROM ubuntu:24.04

# File Author / Maintainer
LABEL maintainer="kosson@gmail.com"

ENV PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
ENV DEBIAN_FRONTEND=noninteractive
ENV REFRESHED_AT=2026-05-8

# ubuntu:24.04 ships with a pre-created 'ubuntu' user at UID 1000.
# koha-create assigns the next available UID to kohadev-koha, which becomes 1001.
# run.sh only calls usermod when LOCAL_USER_ID != 1000, so the mismatch is never fixed
# and kohadev-koha cannot write to the host-mounted Koha repo (owned by UID 1000).
# Removing the ubuntu user here frees UID 1000 for kohadev-koha.
RUN userdel -r ubuntu 2>/dev/null || true

# archive.ubuntu.com routes through Cloudflare CDN (172.66.152.176), which stalls
# TCP connections for certain packages (e.g. liblsan0) at exactly 150 s on Windows
# WSL2 builds due to the Hyper-V NAT conntrack idle timeout. The stall is a CDN
# cache-miss: the CDN accepts the connection but delivers zero bytes while it fetches
# from the origin, then the NAT kills it. azure.archive.ubuntu.com is a Microsoft-
# hosted direct Ubuntu mirror with no CDN stalling layer.
# Activate this replacement if you see 150-second stalls in apt-get update/install logs on Windows if desperate.

RUN sed -i \
       's|http://archive.ubuntu.com/ubuntu|http://azure.archive.ubuntu.com/ubuntu|g;'\
's|http://security.ubuntu.com/ubuntu|http://azure.archive.ubuntu.com/ubuntu|g' \
       /etc/apt/sources.list.d/ubuntu.sources

# apt settings: retries, generous timeout, Queue-Mode "host", and clock-skew tolerance.
#
# Check-Valid-Until "false": On Windows/WSL2/Docker Desktop the container clock can
# lag real time by several minutes after the host wakes from sleep (Hyper-V VM clock
# drift).  apt then refuses to use InRelease files it just downloaded because they
# appear to be "from the future", leaving repositories like noble-updates without a
# package index — packages found only there fail with "Unable to locate package".
# Disabling the validity window is safe for Dockerfile builds; it does not skip
# signature verification (the gpg signature check is unaffected).
#
# Queue-Mode "host": creates one sequential download queue per hostname so that
# connections are always actively transferring data. With the azure mirror this means
# one continuous stream, which prevents the Hyper-V NAT conntrack 150-second idle
# timeout from killing a stalled CDN connection mid-download.
# Acquire::Max-FutureTime: the Docker Desktop / WSL2 Hyper-V VM clock can lag
# real time by several minutes after the host wakes from sleep.  apt uses the
# Release file's Date field to detect this; if Date appears to be in the future
# by more than Max-FutureTime seconds (default: 10), apt refuses the repository
# with "not valid yet" and skips its package index, causing installs to fail.
# 86400 = 24 h, covering any realistic clock drift without disabling the check.
# NOTE: Acquire::Check-Valid-Until controls the Valid-Until (expiry) field and
# is unrelated to this problem.
RUN echo 'Acquire::Retries "8";'                    >  /etc/apt/apt.conf.d/80-retries \
    && echo 'Acquire::http::Timeout "600";'          >> /etc/apt/apt.conf.d/80-retries \
    && echo 'Acquire::https::Timeout "600";'         >> /etc/apt/apt.conf.d/80-retries \
    && echo 'Acquire::Queue-Mode "host";'            >> /etc/apt/apt.conf.d/80-retries \
    && echo 'Acquire::Max-FutureTime "86400";'       >> /etc/apt/apt.conf.d/80-retries

# Install packages with retries to survive intermittent mirror/network failures.
RUN cat > /usr/local/bin/apt-install-retry <<'EOF'
#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
    echo "Usage: apt-install-retry <package> [package ...]" >&2
    exit 2
fi

attempt=1
max_attempts=4
while [ "$attempt" -le "$max_attempts" ]; do
    # -o Acquire::Max-FutureTime=86400: accept Release files whose Date is up
    # to 24 h in the future, tolerating WSL2/Hyper-V VM clock drift after
    # the host wakes from sleep. The conf file also sets this, but passing
    # it inline ensures it is honoured even before the conf layer is cached.
    if apt-get -o Acquire::Max-FutureTime=86400 update \
       && apt-get -y install "$@"; then
        rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
        exit 0
    fi

    if [ "$attempt" -eq "$max_attempts" ]; then
        echo "apt-install-retry: failed after ${max_attempts} attempts" >&2
        exit 1
    fi

    echo "apt-install-retry: attempt ${attempt} failed; retrying..." >&2
    # Do NOT apt-get clean here — keep partial .deb files so apt can resume
    # them on the next attempt via HTTP Range requests instead of restarting.
    rm -rf /var/lib/apt/lists/*
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
done
EOF
RUN sed -i 's/\r$//' /usr/local/bin/apt-install-retry \
    && chmod +x /usr/local/bin/apt-install-retry

# Install base packages (Ubuntu 24.04 Noble)
RUN /bin/sh /usr/local/bin/apt-install-retry \
        apache2 \
        build-essential \
        codespell \
        cpanminus \
        git \
        lsb-release \
        tig \
        libcarp-always-perl \
        libgit-repository-perl \
        libmemcached-tools \
        libmodule-install-perl \
        libperl-critic-perl \
        libtest-differences-perl \
        libtest-perl-critic-perl \
        libtest-perl-critic-progressive-perl \
        libfile-chdir-perl \
        libdata-printer-perl \
        pmtools \
        locales \
        netcat-openbsd \
        python3-gdbm \
        vim \
        nano \
        tmux \
        wget \
        curl \
        apt-transport-https \
        plocate \
        iproute2

# Set locales
RUN    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "fi_FI.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && dpkg-reconfigure locales \
    && /usr/sbin/update-locale LANG=en_US.UTF-8

ENV LANGUAGE=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LC_CTYPE=en_US.UTF-8

# Prepare Apache configuration
RUN a2dismod mpm_event
RUN a2dissite 000-default
RUN a2enmod rewrite \
    headers \
    proxy_http \
    cgi

# Add Koha community repository
RUN curl -s http://debian.koha-community.org/koha/gpg.asc | \
    gpg --dearmor -o /etc/apt/trusted.gpg.d/koha.gpg && \
    chmod 644 /etc/apt/trusted.gpg.d/koha.gpg && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/koha.gpg] http://debian.koha-community.org/koha-staging dev main" >> /etc/apt/sources.list.d/koha.list

# Install koha-common
RUN /bin/sh /usr/local/bin/apt-install-retry \
        koha-common \
    && /etc/init.d/koha-common stop \
    && rm -rf /usr/share/koha/misc/translator/po/*

RUN mkdir /kohadevbox
WORKDIR /kohadevbox

# Install Koha development packages
RUN /bin/sh /usr/local/bin/apt-install-retry \
        perltidy \
        libexpat1-dev \
        libtemplate-plugin-gettext-perl \
        libdevel-cover-perl \
        libmoosex-attribute-env-perl \
        libtest-dbix-class-perl \
        libtap-harness-junit-perl \
        libtext-csv-unicode-perl \
        libdevel-cover-report-clover-perl \
        libwebservice-ils-perl \
        libselenium-remote-driver-perl

# Add nodejs repo
# --no-check-certificate: the nodesource TLS cert uses a "not yet valid" chain
# when the container clock lags real time (WSL2/Hyper-V clock drift after sleep).
# Packages are still GPG-signature-verified via the keyring file.
# The apt conf disables TLS peer verification for deb.nodesource.com only.
RUN wget --no-check-certificate -O- -q https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor \
    | tee /usr/share/keyrings/nodesource.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && echo 'Acquire::https::deb.nodesource.com::Verify-Peer "false";'  >  /etc/apt/apt.conf.d/86-nodesource-insecure \
    && echo 'Acquire::https::deb.nodesource.com::Verify-Host "false";'  >> /etc/apt/apt.conf.d/86-nodesource-insecure

# Add yarn repo
RUN wget -O- -q https://dl.yarnpkg.com/debian/pubkey.gpg \
    | gpg --dearmor \
    | tee /usr/share/keyrings/yarnkey.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" > /etc/apt/sources.list.d/yarn.list

# Install Node.js and Yarn
RUN /bin/sh /usr/local/bin/apt-install-retry \
        nodejs \
        yarn

# Install some tool
RUN yarn global add gulp-cli

# Embed /kohadevbox/node_modules
RUN cd /kohadevbox \
    && wget -q https://gitlab.com/koha-community/Koha/-/raw/main/package.json?inline=false -O package.json \
    && wget -q https://gitlab.com/koha-community/Koha/-/raw/main/yarn.lock?inline=false -O yarn.lock \
    && yarn cache clean \
    && yarn install --modules-folder /kohadevbox/node_modules \
    && mv /root/.cache/Cypress /kohadevbox && chown -R 1000 /kohadevbox/Cypress \
    && rm -f package.json yarn.lock

# Add perl-git-bz
RUN cd /kohadevbox \
    && git clone --depth 1 https://gitlab.com/koha-community/perl-git-bz.git \
    && cd perl-git-bz && cpanm --installdeps . \
    && ln -s /kohadevbox/perl-git-bz/bin/git-bz /usr/bin/git-bz

# Clone helper repositories
RUN cd /kohadevbox \
    && git clone https://gitlab.com/koha-community/koha-misc4dev.git   misc4dev \
    && git clone https://gitlab.com/koha-community/koha-gitify.git     gitify \
    && git clone https://gitlab.com/koha-community/qa-test-tools.git   qa-test-tools \
    && chown -R 1000 misc4dev \
    gitify \
    qa-test-tools

# How-to and utility packages
RUN cd /kohadevbox \
    && git clone https://gitlab.com/koha-community/koha-howto.git howto

# Install utility packages
RUN /bin/sh /usr/local/bin/apt-install-retry \
        bugz \
        inotify-tools

# Install Cypress testing packages (Ubuntu 24.04 Noble: t64 variants, libgconf-2-4 removed)
RUN /bin/sh /usr/local/bin/apt-install-retry \
        libgtk2.0-0t64 \
        libgtk-3-0t64 \
        libgbm-dev \
        libnotify-dev \
        libnss3 \
        libxss1 \
        libasound2t64 \
        libxtst6 \
        xauth \
        xvfb

# download koha-reload-starman
RUN cd /kohadevbox \
    && wget https://gitlab.com/mjames/koha-reload-starman/-/raw/master/koha-reload-starman \
    && chmod 755 koha-reload-starman

VOLUME /kohadevbox/koha

COPY files/run.sh /kohadevbox/
COPY files/templates /kohadevbox/templates
COPY files/git_hooks /kohadevbox/git_hooks
COPY env/defaults.env /kohadevbox/templates/defaults.env

# Ensure Linux line endings even when the repository is checked out with CRLF on Windows.
RUN sed -i 's/\r$//' /kohadevbox/run.sh \
    && find /kohadevbox/templates -type f -exec sed -i 's/\r$//' {} + \
    && find /kohadevbox/git_hooks -type f -exec sed -i 's/\r$//' {} + \
    && chmod +x /kohadevbox/run.sh

EXPOSE 6001 8080 8081

CMD ["/bin/bash", "/kohadevbox/run.sh"]
