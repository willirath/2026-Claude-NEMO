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
    ksh \
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

# Build rebuild_nemo tool for recombining multi-rank output
RUN cd /nemo/tools/REBUILD_NEMO/src && \
    mpif90 -o ../rebuild_nemo.exe rebuild_nemo.f90 \
    -fdefault-real-8 -O3 -ffree-line-length-none \
    -I/usr/include $(nf-config --flibs)

# Override namelist with project-local config (1/5°, adjusted timestep, etc.)
COPY docker/namelist_cfg /nemo/cfgs/GYRE/EXP00/namelist_cfg

WORKDIR /nemo/cfgs/GYRE/EXP00

CMD ["bash"]
