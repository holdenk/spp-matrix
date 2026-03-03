.PHONY: site-configmap predeploy-check

## Generate matrix-site/configmap.yaml from matrix-site/index.html
site-configmap:
	./scripts/generate-site-configmap.sh

## Run predeploy validation checks
predeploy-check:
	./scripts/predeploy-check.sh
