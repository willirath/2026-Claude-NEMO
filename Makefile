IMAGE := nemo-gyre
GHCR_IMAGE := ghcr.io/willirath/2026-claude-nemo
OUTPUT_DIR := output
SIF ?= $(CURDIR)/nemo-gyre.sif
NP ?= 4

.PHONY: all build run analyze postproc postproc-singularity slides clean push

all: build run analyze

build:
	docker build -t $(IMAGE) .

run:
	mkdir -p $(OUTPUT_DIR)
	docker run --rm --hostname nemo --cpus 4 --cpuset-cpus 0-3 -v $(CURDIR)/$(OUTPUT_DIR):/output $(IMAGE) \
		bash -c '\
		mpirun --allow-run-as-root -np 4 ./nemo && \
		for f in *_grid_T_0000.nc *_grid_U_0000.nc *_grid_V_0000.nc *_grid_W_0000.nc; do \
			base=$${f%_0000.nc}; \
			/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo $${base} 4 && rm -f $${base}_[0-9][0-9][0-9][0-9].nc; \
		done && \
		/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo mesh_mask 4 && rm -f mesh_mask_[0-9][0-9][0-9][0-9].nc && \
		cp -v *.nc /output/'
	@# Fix IOIPSL '360d' → CF-compliant '360_day' (see analysis/calendar_note.md)
	pixi run python -c "from netCDF4 import Dataset; from glob import glob; [((d:=Dataset(f,'r+')), d['time_counter'].setncattr('calendar','360_day'), d.close()) for f in glob('$(OUTPUT_DIR)/*_grid_*.nc')]"

# _POSTPROC_REBUILD: shared logic run inside a container given /tmp/nc_fix with
# fixed-header copies of the processor files.  Rebuilds and writes combined
# .nc files into /tmp/nc_fix; caller copies them out.
_POSTPROC_REBUILD = \
	cd /tmp/nc_fix && \
	for f in *_grid_T_0000.nc *_grid_U_0000.nc *_grid_V_0000.nc *_grid_W_0000.nc; do \
		if [ -f "$$f" ]; then \
			base=$${f%_0000.nc}; \
			/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo $$base $(NP); \
		fi; \
	done && \
	if [ -f mesh_mask_0000.nc ]; then \
		/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo mesh_mask $(NP); \
	fi

# _POSTPROC_COPY_AND_FIX: copy processor files to a tmpdir, fix headers on
# copies, run the container rebuild, copy combined files back, remove tmpdir.
# $(1) = container invocation up to and including the bind-mount of tmpdir.
define _POSTPROC_COPY_AND_FIX
	@tmpdir=$$(mktemp -d); \
	trap 'rm -rf $$tmpdir' EXIT; \
	cp $(OUTPUT_DIR)/*_[0-9][0-9][0-9][0-9].nc $$tmpdir/ \
		2>/dev/null || { echo "No processor files found in $(OUTPUT_DIR)"; exit 1; }; \
	pixi run python analysis/fix_numrecs.py $$tmpdir; \
	$(1) bash -c '$(_POSTPROC_REBUILD)'; \
	cp $$tmpdir/*_grid_*.nc $(OUTPUT_DIR)/; \
	cp $$tmpdir/mesh_mask.nc $(OUTPUT_DIR)/ 2>/dev/null || true; \
	pixi run python -c "from netCDF4 import Dataset; from glob import glob; \
		[((d:=Dataset(f,'r+')), d['time_counter'].setncattr('calendar','360_day'), \
		d.close()) for f in glob('$(OUTPUT_DIR)/*_grid_*.nc')]"
endef

postproc:
	$(call _POSTPROC_COPY_AND_FIX,\
		docker run --rm --hostname nemo -v $$tmpdir:/tmp/nc_fix $(IMAGE))

postproc-singularity:
	$(call _POSTPROC_COPY_AND_FIX,\
		singularity exec --bind $$tmpdir:/tmp/nc_fix $(SIF))

analyze:
	pixi run jupyter execute --inplace analysis/ssh.ipynb analysis/sst.ipynb analysis/circulation.ipynb analysis/heat_salt.ipynb analysis/forcing_ke.ipynb analysis/eddies.ipynb analysis/vorticity.ipynb

slides:
	@echo "Serving slides at http://localhost:8000/slides.html"
	cd docs && pixi run python -m http.server 8000

push:
	docker buildx build --platform linux/amd64 \
		-t $(GHCR_IMAGE):latest \
		-t $(GHCR_IMAGE):$(shell git rev-parse --short HEAD) \
		--push .

clean:
	rm -rf $(OUTPUT_DIR)
