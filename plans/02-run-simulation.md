# Milestone 2: Run GYRE_PISCES simulation and verify output

## Goal

Execute the NEMO GYRE_PISCES simulation inside Docker and confirm it
produces valid NetCDF output files.

## Approach

### Run command
```bash
make run
```
This does:
1. Creates `output/` directory
2. `docker run` with volume mount at `/output`
3. `mpirun --allow-run-as-root -np 1 ./nemo`
4. Copies `*.nc` files to `/output` (→ host `output/`)

### Expected output
IOIPSL writes `grid_{T,U,V,W}_*.nc` files every `nn_write` timesteps.
Default `nn_write = 60`, timestep `rn_Dt = 14400s` (4 hours), so output
every 60 × 4h = 10 days.

Default run length: `nn_itend = 4320` timesteps = 720 days ≈ 2 years.

### Verification
1. Simulation exits cleanly (return code 0, "AAAAAAAA" end banner)
2. NetCDF files exist in `output/`
3. Quick `ncdump -h` or xarray check shows expected variables
   (temperature, salinity, velocities, SSH)

## Possible issues
- Long run time for 4320 timesteps — may want to shorten `nn_itend`
  for first test
- Memory usage with MPI on constrained Docker
- IOIPSL output format quirks (time axis, variable names)

## Files modified
- None expected — just running `make run`
- May need to adjust namelist if run is too long or output is missing
