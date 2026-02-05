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
COPY docker/arch-docker.fcm /opt/nemo-code/arch/arch-docker.fcm

# Copy NEMO source
COPY nemo /opt/nemo-code

# Copy project-specific configuration (external to submodule)
COPY configs /opt/nemo-configs

WORKDIR /opt/nemo-code

# Build NEMO with external GYRE_DOCKER config
# -r GYRE_PISCES : base reference configuration
# -n GYRE_DOCKER : new configuration name (matches configs/GYRE_DOCKER/)
# -t /opt/nemo-configs : external config directory (CPP keys, namelist, MY_SRC)
# -j 4           : parallel compilation
RUN ./makenemo -m docker -r GYRE_PISCES -n GYRE_DOCKER -t /opt/nemo-configs -j 4

# Build rebuild_nemo tool for recombining multi-rank output
RUN cd /opt/nemo-code/tools/REBUILD_NEMO/src && \
    mpif90 -o ../rebuild_nemo.exe rebuild_nemo.f90 \
    -fdefault-real-8 -O3 -ffree-line-length-none \
    -I/usr/include $(nf-config --flibs)

# Set up run directory with symlinks to executable and namelists
# Note: makenemo -t places EXP00 in the external config dir, not nemo-code
RUN mkdir -p /opt/nemo-run && \
    ln -s /opt/nemo-configs/GYRE_DOCKER/EXP00/nemo /opt/nemo-run/nemo && \
    ln -s /opt/nemo-configs/GYRE_DOCKER/EXPREF/namelist_cfg /opt/nemo-run/namelist_cfg && \
    ln -s /opt/nemo-configs/GYRE_DOCKER/EXP00/namelist_ref /opt/nemo-run/namelist_ref

WORKDIR /opt/nemo-run

CMD ["bash"]
