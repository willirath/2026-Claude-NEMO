# GYRE_DOCKER Configuration

NEMO configuration for Dockerized GYRE simulation. Based on `GYRE_PISCES` reference configuration, with physics-only setup (no biogeochemistry).

## Structure

```
GYRE_DOCKER/
├── EXPREF/
│   └── namelist_cfg    # Runtime parameters (resolution, timestep, output)
├── MY_SRC/             # Custom Fortran source (empty — uses GYRE defaults)
│   └── .gitkeep
├── cpp_GYRE_DOCKER.fcm # CPP keys (compile-time feature selection)
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

## MY_SRC

Empty by default — uses standard GYRE user-defined modules from NEMO source:
- `usrdef_hgr.F90` — Horizontal grid (beta-plane, 45° rotation)
- `usrdef_zgr.F90` — Vertical grid
- `usrdef_sbc.F90` — Surface forcing (analytical wind stress)
- `usrdef_istate.F90` — Initial state

To customize forcing or initial conditions, copy the relevant `usrdef_*.F90` from `nemo/src/OCE/USR/` into `MY_SRC/` and modify.

## Build

Used by Docker via `makenemo -t`:
```bash
./makenemo -m docker -r GYRE_PISCES -n GYRE_DOCKER -t /configs -j 4
```
