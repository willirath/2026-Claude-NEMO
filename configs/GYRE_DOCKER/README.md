# GYRE_DOCKER Configuration

NEMO configuration for Dockerized GYRE simulation. Based on `GYRE_PISCES` reference configuration, with physics-only setup (no biogeochemistry).

## Structure

```
GYRE_DOCKER/
├── EXPREF/
│   └── namelist_cfg       # Runtime parameters (resolution, timestep, output)
├── MY_SRC/                # Custom Fortran source overrides
│   └── usrdef_sbc.F90     # Modified surface forcing (see below)
├── cpp_GYRE_DOCKER.fcm    # CPP keys (compile-time feature selection)
└── README.md
```

## CPP Keys

| Key | Purpose | Why |
|-----|---------|-----|
| `key_linssh` | Linear free surface | Simplified SSH dynamics |
| `key_vco_1d` | 1D vertical coordinate | Uniform vertical grid across domain |

**Not included** (present in GYRE_PISCES reference):
- `key_xios` — Using IOIPSL for output instead (simpler, no external dependency)
- `key_top` — No passive tracers or PISCES biogeochemistry

## Key Namelist Parameters

See `EXPREF/namelist_cfg` for full details. Key parameters:

| Parameter | Meaning |
|-----------|---------|
| `nn_GYRE` | Horizontal resolution (1/N degrees) |
| `jpkglo` | Number of vertical levels |
| `rn_Dt` | Timestep (seconds) |
| `nn_itend` | Total number of timesteps |
| `nn_write` | Output frequency (timesteps per output record) |
| `ln_usr` | Analytical forcing (no input files) |

## Physics Configuration

Adapted to match the Bagaeva et al. (2024) 20 km no-backscatter double-gyre baseline:

| Parameter | Setting |
|-----------|---------|
| Viscosity | Biharmonic (bilaplacian), ahm ≈ 6.67×10¹⁰ m⁴/s |
| EOS | Linear, T-dependent only (`ln_seos`, nonlinear terms zeroed) |
| Vertical mixing | Pacanowski-Philander (Richardson-number dependent) |
| Bottom drag | Linear, Cd₀·Uc₀ = 10⁻³ m/s |
| Forcing | Steady (no seasonal cycle), heat restoring −4 W/m²/K, no E-P |
| Run length | 59 years (50 spinup + 9 analysis), timestep 2880 s |

## MY_SRC

Contains `usrdef_sbc.F90`, copied from `nemo/src/OCE/USR/usrdef_sbc.F90` and
modified to match the Bagaeva et al. (2024) 20 km no-backscatter baseline:

| Change | Before | After |
|--------|--------|-------|
| Seasonal cycle | Full cosine modulation on wind + heat | Removed (`zcos_sais1/2 = 0`) |
| Heat restoring | −40 W/m²/K | −4 W/m²/K |
| E-P flux | Sinusoidal freshwater forcing | Zero (salinity conserved) |

The other standard GYRE source files are used unmodified from the submodule:
- `usrdef_hgr.F90` — Horizontal grid (beta-plane, 45° rotation)
- `usrdef_zgr.F90` — Vertical grid
- `usrdef_istate.F90` — Initial state

## Build

Used by Docker via `makenemo -t`:
```bash
./makenemo -m docker -r GYRE_PISCES -n GYRE_DOCKER -t /configs -j 4
```
