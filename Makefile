IMAGE := nemo-gyre
OUTPUT_DIR := output

.PHONY: build run clean

build:
	docker build -t $(IMAGE) .

run:
	mkdir -p $(OUTPUT_DIR)
	docker run --rm -v $(CURDIR)/$(OUTPUT_DIR):/output $(IMAGE) \
		bash -c 'mpirun --allow-run-as-root -np 1 ./nemo && cp -v *.nc /output/ 2>/dev/null || true'

clean:
	rm -rf $(OUTPUT_DIR)
