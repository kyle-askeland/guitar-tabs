# Single entry point for all workflows (SPECS §6).
# API_URL: set to the deployed API for `make run` against AWS, e.g.
#   make run API_URL=$$(cd infra && terraform output -raw api_url)

.PHONY: run test test-backend test-frontend deploy-infra deploy-frontend deploy smoke

run:
	cd frontend && flutter run -d chrome $(if $(API_URL),--dart-define=API_URL=$(API_URL))

test: test-backend test-frontend

test-backend:
	cd backend && npm ci --silent && npm test

test-frontend:
	cd frontend && flutter test

deploy-infra:
	cd infra && terraform init && terraform apply

deploy-frontend:
	$(eval API_URL := $(shell cd infra && terraform output -raw api_url))
	$(eval BUCKET := $(shell cd infra && terraform output -raw site_bucket))
	$(eval DIST_ID := $(shell cd infra && terraform output -raw cloudfront_distribution_id))
	cd frontend && flutter build web --release --dart-define=API_URL=$(API_URL)
	aws s3 sync frontend/build/web s3://$(BUCKET) --delete
	aws cloudfront create-invalidation --distribution-id $(DIST_ID) --paths '/*'

deploy: deploy-infra deploy-frontend

smoke:
	curl -fsS $$(cd infra && terraform output -raw api_url)/songs | head -c 500; echo
