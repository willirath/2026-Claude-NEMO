# Adapt GYRE_DOCKER to Match Bagaeva et al. (2024) 20 km No-Backscatter Setup

Goal: make our NEMO GYRE as comparable as possible to the FESOM2 double-gyre
baseline in Bagaeva et al. (2024, JAMES, doi:10.1029/2023MS003972), so that
differences in the vorticity snapshots reflect only unavoidable model
differences (structured vs. unstructured grid, C-grid vs. quasi-B-grid).

## Changes

### Namelist-only changes (`namelist_cfg`)

| # | Parameter | Current | Target | Namelist block |
|---|-----------|---------|--------|----------------|
| 1 | Viscosity operator | Laplacian, ahm = 20 000 m²/s | **Biharmonic**, ahm = 1/12 · Uv · Lv³ | `&namdyn_ldf` |
| 2 | Equation of state | EOS-80 (nonlinear) | **Linear S-EOS** (T-dependent only) | `&nameos` |
| 3 | Vertical mixing | TKE closure | **Pacanowski-Philander** (Richardson-number) | `&namzdf`, `&namzdf_ric` |
| 4 | Bottom friction | Nonlinear (quadratic) Cd₀=10⁻³ | **Linear** drag, Cd₀·Uc₀ = 10⁻³ m/s | `&namdrg`, `&namdrg_bot` |
| 5 | Run length | 1 year (nn_itend=10800) | **59 years** (50 spinup + 9 analysis) | `&namrun` |

### Source-code changes (`MY_SRC/usrdef_sbc.F90`)

| # | Parameter | Current | Target |
|---|-----------|---------|--------|
| 6 | Seasonal cycle | Present (wind, heat, E-P) | **Removed** — set `zcos_sais1=0`, `zcos_sais2=0` |
| 7 | Heat flux restoring | ztrp = −40 W/m²/K | **ztrp = −4 W/m²/K** |
| 8 | Freshwater flux (E-P) | Active (evap − precip) | **Zero** — Bagaeva has constant salinity, no E-P |

### Kept as-is (unavoidable or minor differences)

| Parameter | GYRE_DOCKER | Bagaeva | Reason to keep |
|-----------|------------|---------|----------------|
| Vertical levels | 31 (MI96 formula) | 40 (9 m → 370 m) | Retuning zgr coefficients is non-trivial; 31 levels is adequate |
| Bottom depth | ~4300 m | 4000 m | Tied to vertical grid formula |
| Domain geometry | 3180 × 2120 km | 3140 × 2350 km | Hardcoded in NEMO GYRE usrdef_hgr |
| Biharmonic coefficient | Constant (NEMO) | Flow-aware (FESOM2) | NEMO doesn't have Juricke et al. flow-aware viscosity |
| Momentum advection | Vector-invariant 2nd order | 3rd-order upwind + 4th-order central | Fundamental model difference |
| Tracer diffusion | Laplacian iso-neutral, 200 m²/s | Isoneutral K → "no mixing" (linear EOS) | With linear EOS + constant S, iso-neutral ≈ isothermal, so tracer diffusion has minimal effect anyway |

## Detail: Biharmonic Viscosity Coefficient

NEMO formula: `ahm = 1/12 · Uv · Lv³`

Bagaeva's FESOM2 uses flow-aware biharmonic with γ₀ = 0.005 m/s (DG 20 km).
No direct translation exists. We choose Uv and Lv to give a moderate biharmonic
viscosity appropriate for 20 km:

- `rn_Uv = 0.1 m/s`, `rn_Lv = 20e3 m`
- ahm = 1/12 × 0.1 × (20000)³ = **6.67 × 10¹⁰ m⁴/s**

This is within the typical range for eddy-permitting models (~10¹⁰–10¹¹ m⁴/s).

## Detail: Linear Bottom Drag

NEMO linear drag: τ_bot = Cd₀ · Uc₀ · u

Bagaeva: Cd = 0.001 (linear, units m/s)

→ Set `rn_Cd0 = 1.e-3`, `rn_Uc0 = 1.0` so Cd₀ · Uc₀ = 10⁻³ m/s.

## Detail: Linear EOS

Set `ln_seos = .true.` with all nonlinear coefficients zeroed:
- `rn_a0 = 1.655e-1` (thermal expansion, NEMO default)
- `rn_b0 = 0.0` (no haline contraction — S is constant)
- `rn_lambda1/2 = 0`, `rn_mu1/2 = 0`, `rn_nu = 0`

## Detail: Run Length (59 years)

With rn_Dt = 2880 s and 360-day calendar:
- Steps/year = 360 × 86400 / 2880 = 10800
- 59 years = 59 × 10800 = **637200** steps
- Restart at 50 years = 50 × 10800 = **540000** steps

## Files Modified

1. `configs/GYRE_DOCKER/EXPREF/namelist_cfg` — all namelist changes
2. `configs/GYRE_DOCKER/MY_SRC/usrdef_sbc.F90` — new file (override)

## Verification

1. `make build` — Docker image must compile with biharmonic + zdfric
2. `make run` (short test, e.g. 1 year) — model runs without crashing
3. Check `ocean.output` for correct parameter echo (biharmonic, PP mixing, linear EOS, linear drag)
4. Full 59-year run on NESH, then compare vorticity snapshot with Bagaeva Fig. 10
