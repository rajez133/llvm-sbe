FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    meson \
    git \
    python3 \
    python3-pip \
    python3-setuptools \
    libffi-dev \
    libedit-dev \
    libncurses-dev \
    zlib1g-dev \
    libxml2-dev \
    libssl-dev \
    vim \
    file \
    bsdmainutils \
    gcc-powerpc-linux-gnu \
    g++-powerpc-linux-gnu \
    binutils-powerpc-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
CMD ["/bin/bash"]
