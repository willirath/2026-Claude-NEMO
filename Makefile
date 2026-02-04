IMAGE := nemo-gyre
OUTPUT_DIR := output

.PHONY: build run clean

build:
	docker build -t $(IMAGE) .

run:
	mkdir -p $(OUTPUT_DIR)
	docker run --rm --hostname nemo -v $(CURDIR)/$(OUTPUT_DIR):/output $(IMAGE) \
		bash -c 'mpirun --allow-run-as-root -np 1 ./nemo && cp -v *.nc /output/'

clean:
	rm -rf $(OUTPUT_DIR)
