FROM --platform=linux/amd64 fedora:40 AS build

# DEP STUFF - Fedora packages for building Python and cinderx
RUN dnf install -y \
    gcc \
    gcc-c++ \
    make \
    ccache \
    curl \
    cmake \
    gdb \
    git \
    lcov \
    bzip2-devel \
    libffi-devel \
    gdbm-devel \
    xz-devel \
    ncurses-devel \
    readline-devel \
    sqlite-devel \
    openssl-devel \
    tk-devel \
    libuuid-devel \
    xorg-x11-server-Xvfb \
    zlib-devel \
    python3 \
    python3-pip \
    wget \
    which \
    expat-devel \
    && dnf clean all

# CINDER STUFF - copy and build (rarely changes)
COPY --chmod=0755 cinder/ /cinder/

WORKDIR /cinder
RUN ./configure \
    CFLAGS="-Wno-error -Wno-error=strict-prototypes" \
    CXXFLAGS="-Wno-error" \
    && make -j$(nproc) CFLAGS="-Wno-error -Wno-error=strict-prototypes"

WORKDIR /cinder/cinderx
RUN ./build.sh --build-root /cinder --python-bin /cinder/python --output-dir /cinder


ENV PATH="/cinder:${PATH}"
ENV PYTHONPATH="/cinder:/cinder/cinderx/PythonLib"

# DEV TOOLS (stable, rarely change)
WORKDIR /root

COPY jitlist_main.txt /jitlist_main.txt
COPY --chmod=0755 scripts/ /scripts/
COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]