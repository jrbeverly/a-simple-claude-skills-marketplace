.PHONY: index lint validate

index:
	bash scripts/catalog/generate-index.sh

lint:
	bash scripts/lint/lint.sh

validate:
	bash scripts/validate/validate.sh
