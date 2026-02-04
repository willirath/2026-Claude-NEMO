FROM debian:bookworm

# System dependencies for building NEMO
RUN apt-get update && apt-get install -y --no-install-recommends \
    gfortran \
    cpp \
    make \
    libopenmpi-dev \
    openmpi-bin \
    libnetcdf-dev \
    libnetcdff-dev \
    libhdf5-dev \
    perl \
    liburi-perl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install architecture file early (changes rarely, aids caching)
COPY docker/arch-docker.fcm /nemo/arch/arch-docker.fcm

# Copy NEMO source
COPY nemo /nemo
WORKDIR /nemo

# Override cpp keys: physics only (no XIOS, no PISCES)
RUN echo 'bld::tool::fppkeys   key_linssh key_vco_1d' \
    > /nemo/cfgs/GYRE_PISCES/cpp_GYRE_PISCES.fcm

# Build NEMO GYRE (derived from GYRE_PISCES base config, without key_top)
RUN ./makenemo -m docker -r GYRE_PISCES -n GYRE -j 4

WORKDIR /nemo/cfgs/GYRE/EXP00

CMD ["bash"]
