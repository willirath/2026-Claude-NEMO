IMAGE := nemo-gyre
OUTPUT_DIR := output

.PHONY: all build run analyze clean

all: build run analyze

build:
	docker build -t $(IMAGE) .

run:
	mkdir -p $(OUTPUT_DIR)
	docker run --rm --hostname nemo -v $(CURDIR)/$(OUTPUT_DIR):/output $(IMAGE) \
		bash -c 'mpirun --allow-run-as-root -np 1 ./nemo && cp -v *.nc /output/'

analyze:
	pixi run jupyter execute --inplace analysis/ssh.ipynb analysis/sst.ipynb analysis/circulation.ipynb analysis/heat_salt.ipynb analysis/forcing_ke.ipynb

clean:
	rm -rf $(OUTPUT_DIR)
