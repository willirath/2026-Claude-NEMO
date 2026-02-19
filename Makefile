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

postproc:
	docker run --rm --hostname nemo -v $(CURDIR)/$(OUTPUT_DIR):/output $(IMAGE) \
		bash -c '\
		cd /output && \
		for f in *_grid_T_0000.nc *_grid_U_0000.nc *_grid_V_0000.nc *_grid_W_0000.nc; do \
			if [ -f "$$f" ]; then \
				base=$${f%_0000.nc}; \
				/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo $$base $(NP); \
			fi; \
		done && \
		if [ -f mesh_mask_0000.nc ]; then \
			/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo mesh_mask $(NP); \
		fi'
	pixi run python -c "from netCDF4 import Dataset; from glob import glob; [((d:=Dataset(f,'r+')), d['time_counter'].setncattr('calendar','360_day'), d.close()) for f in glob('$(OUTPUT_DIR)/*_grid_*.nc')]"

postproc-singularity:
	singularity exec \
		--bind $(CURDIR)/$(OUTPUT_DIR):/opt/nemo-run \
		$(SIF) \
		bash -c '\
		cd /opt/nemo-run && \
		for f in *_grid_T_0000.nc *_grid_U_0000.nc *_grid_V_0000.nc *_grid_W_0000.nc; do \
			if [ -f "$$f" ]; then \
				base=$${f%_0000.nc}; \
				/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo $$base $(NP); \
			fi; \
		done && \
		if [ -f mesh_mask_0000.nc ]; then \
			/opt/nemo-code/tools/REBUILD_NEMO/rebuild_nemo mesh_mask $(NP); \
		fi'
	pixi run python -c "from netCDF4 import Dataset; from glob import glob; [((d:=Dataset(f,'r+')), d['time_counter'].setncattr('calendar','360_day'), d.close()) for f in glob('$(OUTPUT_DIR)/*_grid_*.nc')]"

analyze:
	pixi run jupyter execute --inplace \
		--ExecutePreprocessor.startup_timeout=300 \
		analysis/ssh.ipynb analysis/sst.ipynb analysis/circulation.ipynb analysis/heat_salt.ipynb analysis/forcing_ke.ipynb analysis/eddies.ipynb analysis/vorticity.ipynb

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
