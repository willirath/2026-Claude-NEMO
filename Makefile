IMAGE := nemo-gyre
GHCR_IMAGE := ghcr.io/willirath/2026-claude-nemo
OUTPUT_DIR := output

.PHONY: all build run analyze slides clean push

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

analyze:
	pixi run jupyter execute --inplace analysis/ssh.ipynb analysis/sst.ipynb analysis/circulation.ipynb analysis/heat_salt.ipynb analysis/forcing_ke.ipynb

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
