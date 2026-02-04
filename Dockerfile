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

# Override cpp keys: drop key_xios, keep the rest
RUN echo 'bld::tool::fppkeys   key_top key_linssh key_vco_1d' \
    > /nemo/cfgs/GYRE_PISCES/cpp_GYRE_PISCES.fcm

# Build NEMO GYRE_PISCES
RUN ./makenemo -m docker -r GYRE_PISCES -n MY_GYRE -j 4

WORKDIR /nemo/cfgs/MY_GYRE/EXP00

# Patch PISCES namelist: disable features that need external forcing files
# (par.orca.nc, bathy.orca.nc, hydrofe.orca.nc are not available in GYRE)
RUN sed -i \
    's|&nampisopt.*|\&nampisopt\n   ln_varpar = .false.|' \
    namelist_pisces_cfg \
 && sed -i \
    's|ln_ironsed  =  .true.|ln_ironsed  = .false.|; \
     s|ln_ironice  =  .true.|ln_ironice  = .false.|; \
     s|ln_hydrofe  =  .true.|ln_hydrofe  = .false.|' \
    namelist_pisces_cfg

CMD ["bash"]
