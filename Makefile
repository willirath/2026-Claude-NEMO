IMAGE := nemo-gyre
OUTPUT_DIR := output

.PHONY: all build run analyze clean

all: build run analyze

build:
	docker build -t $(IMAGE) .

run:
	mkdir -p $(OUTPUT_DIR)
	docker run --rm --hostname nemo --cpus 4 -v $(CURDIR)/$(OUTPUT_DIR):/output $(IMAGE) \
		bash -c '\
		mpirun --allow-run-as-root -np 4 ./nemo && \
		for f in *_grid_T_0000.nc *_grid_U_0000.nc *_grid_V_0000.nc *_grid_W_0000.nc; do \
			base=$${f%_0000.nc}; \
			/nemo/tools/REBUILD_NEMO/rebuild_nemo $${base} 4 && rm -f $${base}_[0-9][0-9][0-9][0-9].nc; \
		done && \
		/nemo/tools/REBUILD_NEMO/rebuild_nemo mesh_mask 4 && rm -f mesh_mask_[0-9][0-9][0-9][0-9].nc && \
		cp -v *.nc /output/'

analyze:
	pixi run jupyter execute --inplace analysis/ssh.ipynb analysis/sst.ipynb analysis/circulation.ipynb analysis/heat_salt.ipynb analysis/forcing_ke.ipynb

clean:
	rm -rf $(OUTPUT_DIR)
