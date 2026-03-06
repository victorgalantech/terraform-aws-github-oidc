# =============================================================================
# Bootstrap Makefile
#
# Automates the chicken-and-egg first-deploy sequence and common dev tasks.
#
# USAGE
#   First-time deploy (S3 bucket does not exist yet):
#     make bootstrap-init ENV=dev PROFILE=bootstrap-dev
#     make bootstrap-apply ENV=dev PROFILE=bootstrap-dev
#     make bootstrap-migrate ENV=dev PROFILE=bootstrap-dev
#
#   Subsequent deploys (bucket exists, backend is configured):
#     make plan ENV=dev
#     make apply ENV=dev
#
#   Local quality checks (no AWS credentials needed):
#     make fmt
#     make validate
#     make test
#     make lint
# =============================================================================

ENV     ?= dev
PROFILE ?= bootstrap-$(ENV)
LIVE_DIR = live/$(ENV)/bootstrap
MODULE_DIR = modules/bootstrap

.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "Bootstrap Makefile — available targets:"
	@echo ""
	@echo "  FIRST-TIME DEPLOY (bucket does not exist yet):"
	@echo "    make bootstrap-init    ENV=<dev|qa|prod> PROFILE=<aws-profile>"
	@echo "    make bootstrap-apply   ENV=<dev|qa|prod> PROFILE=<aws-profile>"
	@echo "    make bootstrap-migrate ENV=<dev|qa|prod> PROFILE=<aws-profile>"
	@echo ""
	@echo "  SUBSEQUENT DEPLOYS (bucket already exists):"
	@echo "    make plan              ENV=<dev|qa|prod>"
	@echo "    make apply             ENV=<dev|qa|prod>"
	@echo ""
	@echo "  LOCAL QUALITY CHECKS (no AWS credentials needed):"
	@echo "    make fmt               -- terraform fmt on all modules"
	@echo "    make validate          -- terraform validate on modules/bootstrap"
	@echo "    make test              -- terraform test (mock provider, no AWS)"
	@echo "    make lint              -- tflint with AWS ruleset"
	@echo ""
	@echo "  Defaults: ENV=$(ENV)  PROFILE=$(PROFILE)"
	@echo ""

# -----------------------------------------------------------------------------
# First-time bootstrap sequence
#
# Step 1 — init without backend (S3 bucket does not exist yet).
# Terragrunt remote_state config is skipped; state stored locally.
# -----------------------------------------------------------------------------
.PHONY: bootstrap-init
bootstrap-init:
	@echo "==> [1/3] Init without remote backend (ENV=$(ENV))"
	AWS_PROFILE=$(PROFILE) terragrunt init \
		--terragrunt-working-dir $(LIVE_DIR) \
		-backend=false

# Step 2 — apply locally (creates the S3 bucket + all other resources).
.PHONY: bootstrap-apply
bootstrap-apply:
	@echo "==> [2/3] Apply locally — creates S3 state bucket (ENV=$(ENV))"
	AWS_PROFILE=$(PROFILE) terragrunt apply \
		--terragrunt-working-dir $(LIVE_DIR) \
		-backend=false

# Step 3 — re-init with the real backend and migrate the local state into S3.
.PHONY: bootstrap-migrate
bootstrap-migrate:
	@echo "==> [3/3] Migrate local state → S3 backend (ENV=$(ENV))"
	AWS_PROFILE=$(PROFILE) terragrunt init \
		--terragrunt-working-dir $(LIVE_DIR) \
		-migrate-state -force-copy
	@echo ""
	@echo "Bootstrap complete. Subsequent changes use: make plan ENV=$(ENV)"

# -----------------------------------------------------------------------------
# Subsequent deploys
# -----------------------------------------------------------------------------
.PHONY: plan
plan:
	@echo "==> Terragrunt plan (ENV=$(ENV))"
	AWS_PROFILE=$(PROFILE) terragrunt plan \
		--terragrunt-working-dir $(LIVE_DIR) \
		-detailed-exitcode

.PHONY: apply
apply:
	@echo "==> Terragrunt apply (ENV=$(ENV))"
	AWS_PROFILE=$(PROFILE) terragrunt apply \
		--terragrunt-working-dir $(LIVE_DIR)

# -----------------------------------------------------------------------------
# Local quality checks — no AWS credentials needed
# -----------------------------------------------------------------------------
.PHONY: fmt
fmt:
	@echo "==> terraform fmt (recursive)"
	terraform fmt -recursive modules/

.PHONY: fmt-check
fmt-check:
	@echo "==> terraform fmt --check (recursive)"
	terraform fmt -check -recursive modules/

.PHONY: validate
validate:
	@echo "==> terraform validate"
	cd $(MODULE_DIR) && terraform init -backend=false -input=false > /dev/null && terraform validate

.PHONY: test
test:
	@echo "==> terraform test (mock provider — no real AWS account needed)"
	cd $(MODULE_DIR) && terraform test -no-color

.PHONY: lint
lint:
	@echo "==> tflint (AWS ruleset)"
	cd $(MODULE_DIR) && tflint --init && tflint --format compact
