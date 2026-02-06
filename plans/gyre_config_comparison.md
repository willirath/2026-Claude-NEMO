# Double-Gyre Configuration Comparison

Three implementations of the idealised wind-driven double-gyre test case at
~20 km resolution: the NEMO reference (Lévy et al., 2010), the FESOM2
implementation (Bagaeva et al., 2024), and our GYRE_DOCKER setup.

## Domain geometry

| Parameter | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER (this project) |
|-----------|------------------|-----------------------|---------------------------|
| Model | NEMO (structured Arakawa C-grid) | FESOM2 (unstructured triangular quasi-B-grid) | NEMO (same code as Lévy) |
| Domain size | 3180 × 2120 km | ~3140 × 2350 km (28.3° × 21.2°) | 3180 × 2120 km |
| Horizontal resolution | 106 km (nn_GYRE=1) | 20 km (right-angled triangle short side) | 21.2 km (nn_GYRE=5) |
| Grid points | 32 × 22 | Unstructured (~27k nodes at 20 km) | 152 × 102 |
| Rotation | 45° from east | 45° from east | 45° from east |
| SW corner | 85°W, 29°N | 30°N (left corner) | 85°W, 29°N |
| Geometry | Spherical (beta-plane for f) | Spherical (beta-plane for f) | Spherical (beta-plane for f) |
| Lateral boundaries | Closed, free-slip | Closed (vertical walls) | Closed, free-slip |
| Bottom | Flat | Flat, 4000 m | Flat, ~4300 m (31-level z-coord) |

Note: Lévy 2010 defined the configuration at coarse (~100 km) resolution to
study how refining the grid introduces mesoscale dynamics. The 20 km setups
(Bagaeva and GYRE_DOCKER) are eddy-permitting — the first baroclinic Rossby
deformation radius is ~20 km at the domain centre.

## Vertical grid

| Parameter | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER |
|-----------|------------------|-----------------------|-------------|
| Levels | 31 (z-coordinate, MI96 stretching) | 40 (z-levels, 9 m → 370 m) | 31 (same MI96 formula as Lévy) |
| Surface layer | ~5 m | ~9 m | ~5 m |
| Max depth | ~4300 m (W-level 31) | 4000 m | ~4300 m |
| Vertical coord | Fixed z with linear free surface | z with linear free surface | Fixed z with linear free surface (`key_linssh key_vco_1d`) |

## Equation of state and tracers

| Parameter | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER |
|-----------|------------------|-----------------------|-------------|
| EOS | Linear (T-dependent only) | Linear (T-dependent only) | EOS-80 (full nonlinear; diverges from Lévy) |
| Salinity | Constant | Constant | Active but initialised uniformly |
| Initial T | Analytical (surface ~24°C, decreasing with depth) | Following Pacanowski & Philander (1981) and Lévy (2010): rapid decrease to 500 m, linear to 0°C below | Analytical (same as Lévy source code) |

The EOS choice is a notable difference: GYRE_DOCKER uses `ln_eos80 = .true.`
(the NEMO default) whereas both Lévy and Bagaeva use a linear EOS where
density depends only on temperature. In practice the GYRE configuration's
salinity is nearly uniform so the EOS-80 nonlinearity is minor, but a strict
reproduction of Lévy would use a linear EOS.

## Forcing

| Parameter | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER |
|-----------|------------------|-----------------------|-------------|
| Wind stress | Sinusoidal in latitude, τ₀ = 0.105/√2 ≈ 0.074 Pa per component, with seasonal cycle (±0.015) | Sinusoidal (mean NH pattern), no seasonal cycle | Same as Lévy (with seasonal cycle) |
| Heat flux | Restoring to T* + solar penetration (2-band), retroaction coefficient −40 W/m²/K | Sensible (−γ(T_ocean − T_atm), γ = 4 W/m²/K) + radiative (solar with penetration); no latent flux; no seasonal cycle | Same as Lévy |
| Freshwater | E−P with latent heat; no salt flux | None (salinity constant) | Same as Lévy |

Bagaeva et al. deliberately removed the seasonal cycle to isolate the eddy
parameterisation signal, and simplified the heat flux formulation. The NEMO
GYRE source code (used by both Lévy and GYRE_DOCKER) includes full seasonal
variability in wind, solar radiation, and surface temperature restoring.

## Dynamics and mixing

| Parameter | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER |
|-----------|------------------|-----------------------|-------------|
| Momentum advection | Vector-invariant, energy-conserving | 3rd-order upwind + 4th-order central | Vector-invariant, energy-conserving |
| Tracer advection | FCT (2nd-order) | (not specified) | FCT (2nd-order H+V) |
| Horizontal viscosity | Laplacian, Ahm = ½ × 2.0 × 20 km = 20 000 m²/s | Biharmonic (flow-aware, Juricke et al. 2020) | Laplacian, Ahm = ½ × 2.0 × 20 km = 20 000 m²/s |
| Horizontal diffusion | Laplacian iso-neutral, Aht = ½ × 0.02 × 20 km = 200 m²/s | Not specified explicitly | Laplacian iso-neutral, Aht = 200 m²/s |
| Vertical mixing | TKE closure | Pacanowski-Philander | TKE closure |
| Bottom friction | Non-linear drag | Linear drag (Cd = 0.001) | Non-linear drag |
| Time step | Not specified at 1° | Not specified explicitly | 2880 s (48 min) |
| Coriolis | β-plane, f₀ at domain south edge | β-plane, β = 1.8 × 10⁻¹¹ 1/(m·s) | β-plane, f₀ and β computed at 29°N |

Key differences in dynamics: Bagaeva uses biharmonic viscosity (scale-selective,
less damping of large scales) while NEMO GYRE uses Laplacian viscosity. Bagaeva
also uses Pacanowski-Philander vertical mixing whereas NEMO defaults to TKE.

## Runtime and spinup

| Parameter | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER |
|-----------|------------------|-----------------------|-------------|
| Total integration | 100 years | 59 years (50 + 9) | 1 year |
| Spinup discarded | Not stated explicitly | 50 years | None |
| Analysis period | 100 years (mean fields) | 9 years (time-averaged) | Full run |
| Output frequency | Not specified | Daily | 10-day averages |

Lévy ran 100-year integrations at each resolution (1°, 1/9°, 1/54°) and
analysed time-mean fields. Bagaeva spins up the DG setup for 50 years until
the circulation reaches quasi-equilibrium, then analyses 9-year averages.
GYRE_DOCKER currently runs for 1 year from rest — far too short for
equilibrium, suitable only as a pipeline smoke test.

## Diagnostics

| Diagnostic | NEMO / Lévy 2010 | FESOM2 / Bagaeva 2024 | GYRE_DOCKER |
|------------|------------------|-----------------------|-------------|
| SSH | Mean SSH, gyre transport | Mean SSH (9-yr avg), SSH RMSE vs high-res | SSH temporal variance (map), domain-mean SSH time series |
| SST | Mean SST, thermocline structure | — | Mean SST (map), domain-mean SST time series, meridional SST gradient |
| Surface currents | Mean circulation patterns | Relative vorticity snapshots | Mean current vectors (map), surface KE (map) |
| KE / EKE | — | Surface KE, surface EKE (area-averaged vertical profiles, % of 10 km reference) | Total volume-integrated KE time series |
| APE / buoyancy flux | — | Buoyancy flux b'w' (vertical profiles), vertically integrated b'w' | — |
| Vertical velocity | — | RMS vertical velocity anomaly (vertical profiles) | — |
| Spectra | — | KE and dissipation spectra (Fourier, 9-yr averaged daily output) | — |
| Density / stratification | Isopycnal slopes, thermocline depth | Vertical density profiles along 15° lon | — |
| Heat / salt | — | — | Surface heat flux (map + zonal mean), total heat content time series, volume-mean salinity time series |
| Forcing | — | — | Wind stress vectors (map) |
| EOF analysis | — | SSH EOFs + principal components | — |

Bagaeva's diagnostics focus on evaluating the backscatter parameterisation:
comparing 20 km runs (with/without backscatter) against a 10 km reference.
The key metrics are EKE recovery (%), vertical profiles of w_RMS and buoyancy
flux, and KE spectra. Lévy focused on how sub-mesoscale resolution changes the
mean gyre circulation and thermocline structure. GYRE_DOCKER provides basic
sanity-check plots for a short integration.

## Summary

The three configurations share the same conceptual setup — a rectangular,
45°-rotated, beta-plane basin driven by sinusoidal wind stress — but differ in
several details:

1. **Grid type**: NEMO uses a structured Arakawa C-grid; FESOM2 uses
   unstructured triangles. At 20 km both are eddy-permitting.
2. **Viscosity operator**: Laplacian (NEMO) vs biharmonic (FESOM2). This is
   the most dynamically significant difference — biharmonic viscosity is less
   damping at the mesoscale.
3. **Heat flux and seasonal cycle**: NEMO includes a seasonal cycle and
   restoring-style heat flux; Bagaeva removes seasonality and simplifies to a
   sensible + radiative formulation with a small coupling coefficient
   (4 W/m²/K vs NEMO's 40 W/m²/K restoring).
4. **EOS**: Lévy and Bagaeva both use a linear EOS; GYRE_DOCKER uses the
   nonlinear EOS-80 (a minor inconsistency with Lévy's design).
5. **Vertical grid**: FESOM2 uses 40 levels to 4000 m; NEMO uses 31 levels to
   ~4300 m.

## References

- Lévy, M., et al. (2010). Modifications of gyre circulation by sub-mesoscale
  physics. *Ocean Modelling*, 34(1–2), 1–15.
  doi:10.1016/j.ocemod.2010.04.001

- Bagaeva, E., et al. (2024). Advancing Eddy Parameterizations: Dynamic Energy
  Backscatter and the Role of Subgrid Energy Advection and Stochastic Forcing.
  *J. Adv. Model. Earth Syst.*, 16(4), e2023MS003972.
  doi:10.1029/2023MS003972
