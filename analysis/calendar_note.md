# NEMO IOIPSL calendar attribute vs CF conventions

IOIPSL writes `calendar = "360d"` to the NetCDF time axis ([`nemo/ext/IOIPSL/src/calendar.f90:674`](../nemo/ext/IOIPSL/src/calendar.f90)).
The [CF conventions (Section 4.4)](https://cfconventions.org/Data/cf-conventions/cf-conventions-1.7/build/ch04s04.html) define the valid value as `360_day` — "All years are 360 days divided into 30 day months."
The string `360d` is not in the CF calendar vocabulary (`standard`, `proleptic_gregorian`, `noleap`/`365_day`, `all_leap`/`366_day`, `360_day`, `julian`, `none`), so xarray/cftime refuse to decode the time axis, forcing `decode_times=False` as a workaround.
We fix this post-rebuild by patching the attribute in-place with `ncatted`.
