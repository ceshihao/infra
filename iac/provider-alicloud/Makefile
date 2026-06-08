ENV := $(shell cat ../../.last_used_env || echo "not-set")
ENV_FILE := ../../.env.${ENV}
-include ${ENV_FILE}

# Switch Provider: run `make <target> PROVIDER=alicloud` from repo root.
# The top-level Makefile enters here via $(MAKE) -C iac/provider-alicloud.

TF := $(shell which terraform)
PACKER := $(shell which packer)

TF_VAR_FILE := ./.terraform.${ENV}.tfvars

# AlibabaCloud equivalents to AWS concepts:
#   AWS_ACCOUNT_ID  -> ALICLOUD_ACCOUNT_ID  (primary account UID, used for resource naming/ACR namespace)
#   AWS_REGION      -> ALICLOUD_REGION      (e.g. cn-hangzhou)
#   AWS_PROFILE     -> ALICLOUD_PROFILE     (profile name configured in aliyun-cli)
#   ECR             -> ACR (Enterprise / Personal Edition); Enterprise (alicloud_cr_ee_*) recommended
#   S3 bucket       -> OSS bucket
#   Secrets Manager -> KMS Secret (data_key_secret) / or Parameter Store
#   Route 53        -> Cloudflare (same as GCP/AWS; mainland China ICP-registered domains use DCDN/Cloudflare China Network)
TERRAFORM_STATE_BUCKET ?= $(ALICLOUD_ACCOUNT_ID)-terraform-state
BUCKET_PREFIX           ?= $(PREFIX)$(ALICLOUD_ACCOUNT_ID)-

define tfvar
TF_VAR_$(shell echo $(1) | tr A-Z a-z)=$$(if $$($(1)),$$($(1)),$$(error $(1) is not set))
endef

tf_vars := ALICLOUD_PROFILE=$(ALICLOUD_PROFILE) ALICLOUD_REGION=$(ALICLOUD_REGION) \
	TF_VAR_environment=$(TERRAFORM_ENVIRONMENT) \
	$(call tfvar, PREFIX) \
	$(call tfvar, DOMAIN_NAME) \
	$(call tfvar, BUCKET_PREFIX) \
	$(call tfvar, CLIENT_CLUSTER_SIZE) \
	$(call tfvar, BUILD_CLUSTER_SIZE) \
	$(call tfvar, API_CLUSTER_SIZE) \
	$(call tfvar, CONTROL_SERVER_CLUSTER_SIZE) \
	$(call tfvar, CLICKHOUSE_CLUSTER_SIZE) \
	$(call tfvar, INGRESS_COUNT) \
	$(call tfvar, CLIENT_PROXY_COUNT) \
	$(call tfvar, ALLOW_FORCE_DESTROY)

# ------------------------------------------------------------------------
# Provider login: log local docker into ACR Enterprise / Personal Edition
# ------------------------------------------------------------------------
.PHONY: provider-login
provider-login:
	@echo "Login to AlibabaCloud Container Registry"
	# Enterprise Edition (recommended for production)
	# Note: EE user/password requires a one-time temp credential (1h) via cr_ee GetAuthorizationToken API.
	# Below is the aliyun-cli pattern:
	@if [ -n "$(ACR_EE_INSTANCE_ID)" ]; then \
		aliyun cr GetAuthorizationToken --InstanceId $(ACR_EE_INSTANCE_ID) --region $(ALICLOUD_REGION) | \
			jq -r '.AuthorizationToken' | \
			docker login --username "$(shell aliyun cr GetAuthorizationToken --InstanceId $(ACR_EE_INSTANCE_ID) --region $(ALICLOUD_REGION) | jq -r '.TempUsername')" --password-stdin \
			$(ACR_EE_INSTANCE_ID).$(ALICLOUD_REGION).cr.aliyuncs.com; \
	else \
		echo "ACR_EE_INSTANCE_ID not set – falling back to personal ACR"; \
		docker login --username=$(ALICLOUD_ACR_USERNAME) --password=$(ALICLOUD_ACR_PASSWORD) registry.$(ALICLOUD_REGION).aliyuncs.com; \
	fi

# ------------------------------------------------------------------------
# Initialization: create OSS remote state bucket + bootstrap init module
# ------------------------------------------------------------------------
.PHONY: init
init:
	@echo "Ensure OSS bucket for terraform state exists: $(TERRAFORM_STATE_BUCKET)"
	@if ! ossutil ls oss://$(TERRAFORM_STATE_BUCKET) > /dev/null 2>&1; then \
		ossutil mb oss://$(TERRAFORM_STATE_BUCKET) --region $(ALICLOUD_REGION); \
	fi
	$(tf_vars) $(TF) init -upgrade -reconfigure \
		-backend-config="bucket=$(TERRAFORM_STATE_BUCKET)" \
		-backend-config="prefix=terraform/orchestration/state" \
		-backend-config="region=$(ALICLOUD_REGION)"
	$(tf_vars) $(TF) apply -target=module.init -input=false -compact-warnings

# Full plan
.PHONY: plan
plan:
	$(tf_vars) $(TF) fmt -recursive
	$(tf_vars) $(TF) validate
	$(tf_vars) $(TF) plan -out=.tfplan.$(ENV) -compact-warnings -detailed-exitcode

# Plan only job-* modules (cloud-agnostic layer)
.PHONY: plan-only-jobs
plan-only-jobs:
	$(tf_vars) $(TF) plan -out=.tfplan.$(ENV) -compact-warnings -target=module.nomad

# Plan excluding nomad sub-module (for infra-only changes)
.PHONY: plan-without-jobs
plan-without-jobs:
	$(tf_vars) $(TF) plan -out=.tfplan.$(ENV) -compact-warnings \
		-target=module.init -target=module.cluster

.PHONY: apply
apply:
	$(tf_vars) $(TF) apply -auto-approve -compact-warnings -input=false .tfplan.$(ENV)

.PHONY: apply-init
apply-init:
	$(tf_vars) $(TF) apply -target=module.init -input=false -compact-warnings -auto-approve

.PHONY: state-migrate
state-migrate:
	$(tf_vars) $(TF) init -migrate-state \
		-backend-config="bucket=$(TERRAFORM_STATE_BUCKET)" \
		-backend-config="prefix=terraform/orchestration/state" \
		-backend-config="region=$(ALICLOUD_REGION)"

# Rename existing resources in state (useful when migrating from GCP/AWS to alicloud naming)
.PHONY: move
move:
	@if [ -z "$(SRC)" ] || [ -z "$(DST)" ]; then \
		echo "Usage: make move SRC=<src.addr> DST=<dst.addr>"; exit 1; \
	fi
	$(tf_vars) $(TF) state mv "$(SRC)" "$(DST)"

.PHONY: destroy
destroy:
	$(tf_vars) $(TF) destroy -compact-warnings

# ------------------------------------------------------------------------
# Packer: build Nomad cluster ECS image (based on ECS Bare Metal ebmg/ebmgn)
# ------------------------------------------------------------------------
.PHONY: build-cluster-disk-image
build-cluster-disk-image:
	@cd nomad-cluster-disk-image && \
		$(PACKER) init . && \
		$(PACKER) build \
			-var "alicloud_region=$(ALICLOUD_REGION)" \
			-var "alicloud_profile=$(ALICLOUD_PROFILE)" \
			-var "prefix=$(PREFIX)" \
			.
