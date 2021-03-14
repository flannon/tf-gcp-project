#!/bin/bash

#set -e
#
#[[ -z $PROJECT_NAME || -z $PROJECT_ID || -z $ZONE || -z $GCP_EMAIL ]] && \
#  printf "export environment variables\n PROJECT_NAME=\n PROJECT_ID=\n ZONE=\n GCP_EMAIL=\n" \
#  echo "Exiting" \
#  && exit 3

set -euo pipefail

project_config () {
cat << _EOF_ > ~/.config/gcloud/configurations/config_tf-project
[core]
account = $GCP_EMAIL
project = $PROJECT_ID

[compute]
zone = $ZONE
region = $REGION
_EOF_
}

[[ -d ./.terraform ]] && echo "Terraform configuration exits." && exit 1

ACCOUNT="./account.json"
ACCOUNT_CREDENTIALS_PATH="./account.json"
GOOGLE_PROVIDER_VERSION="3.38.0"

echo "Enter project_name:" && \
read PROJECT_NAME && \

echo "Enter project_id:" && \
read PROJECT_ID  && \

CONFIGPATH="${HOME}/.config/gcloud/configurations/config_${PROJECT_NAME}"

[[ ! -f ${HOME}/.config/gcloud/configurations/config_fj5-dev ]] && \
  echo "Enter default zone:" && \
  read ZONE && \

  REGION=$(echo $ZONE | sed 's/.\{2\}$//') && \
  project_config || \
  # If configuration exits pull value from it.
  #PROJECT_ID=$(grep project $CONFIGPATH | sed s/'project = '//) && \
  #PROJECT_NAME=$(gcloud projects list --filter=${PROJECT_NAME} --format='value(name)') && \
  ZONE=$(grep zone $CONFIGPATH | sed s/'zone = '//) && \
  REGION=$(grep zone $CONFIGPATH | sed s/'region = '//) 
  
gcloud config configurations activate $PROJECT_NAME

PROJECT_NUMBER=$(gcloud projects list --filter=${PROJECT_NAME}  --format='value(PROJECT_NUMBER)')
REMOTE_STATE_BUCKET="tf-${PROJECT_ID}"
REMOTE_STATE_PREFIX="/"


BUCKET_STATE=
for i in $(gsutil ls); do
  [[ ${i} == "gs://${REMOTE_STATE_BUCKET}/" ]] && \
    BUCKET_STATE=true
done
echo "_BUCKET_STATE: $BUCKET_STATE"
[[ $BUCKET_STATE != "true" ]] && \
  echo "Making terraform state bucket: $REMOTE_STATE_BUCKET" && \
  gsutil mb gs://${REMOTE_STATE_BUCKET} && \
  gsutil versioning set on gs://${REMOTE_STATE_BUCKET}

NETWORK=$(gcloud compute networks list --format='value(Name)' --filter="name != default")
SA_NAME="tf-project-admin"
SA_STATE=$(gcloud iam service-accounts list --format='value("DISPLAY NAME")' --filter=${SA_NAME})

echo "terraform service account: $SA_NAME"
# check if svc acct exits
[[ -z "$SA_STATE" ]] && \
  gcloud iam service-accounts create ${SA_NAME} 

SA_STATE=$(gcloud iam service-accounts list --format='value("DISPLAY NAME")' --filter=${SA_NAME})
[[ -z "$SA_STATE" ]] && \
  gcloud iam service-accounts update ${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --display-name $SA_NAME && \
  gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --role roles/editor && \
  gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --role roles/iam.serviceAccountUser && \
  gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --role roles/secretmanager.secretAccessor && \
  ###
  gcloud iam service-accounts keys create ${ACCOUNT} --iam-account ${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com 

# cloudbuilder roles
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role roles/iam.serviceAccountUser && \
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com --role roles/secretmanager.secretAccessor && \

# enable apis
gcloud services enable cloudresourcemanager.googleapis.com


# Functions   !+
TAB="$(printf '\t')"
mkfile () {
[[ -f Makefile  || -f makefile ]] && echo "Makefile exists" && exit 2 || \
  cat <<- MAKEFILE > Makefile
.ONESHELL:
.SHELL := /usr/bin/bash
.PHONY: apply destroy destroy-target plan-destroy plan plan-target prep upgrade output build
BUILD_CONFIG="cloudbuild.yaml"
BUILD_DIR="."
PROJECT_ID=\$(shell gcloud config list --format 'value(core.project)' 2>/dev/null)
#PROJECT_NAME=\$(shell gcloud projects describe \$(PROJECT_ID) --format='value(Name)')
PROJECT=\$(shell gcloud projects describe \$(PROJECT_ID) --format='value(Name)')
PROJECT_NUMBER=\$(shell gcloud projects describe \$(PROJECT_ID) --format='value(projectNumber)')
SERVICE="$1"
# Set bucket to terraform backend bucket name
GCS_BUCKET="${REMOTE_STATE_BUCKET}"
GCP_CREDENTIALS="${ACCOUNT_CREDENTIALS_PATH}"
PREFIX="${REMOTE_STATE_PREFIX}"
CURRENT_FOLDER=\$(shell basename "\$\$(pwd)")
BOLD=\$(shell tput bold)
RED=\$(shell tput setaf 1)
GREEN=\$(shell tput setaf 2)
YELLOW=\$(shell tput setaf 3)
RESET=\$(shell tput sgr0)
TF_CMD="terraform"
HELM_DEBUG="HELM_DEBUG=1"

help:
${TAB}@grep -E '^[a-zA-Z_-]+:.*?## .*\$\$' \$(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", \$\$1, \$\$2}'

set-env:
${TAB}@if [ -z \$(PROJECT) ]; then \
${TAB}${TAB}echo "\$(BOLD)\$(RED)PROJECT was not set\$(RESET)"; \
${TAB}${TAB}ERROR=1; \
${TAB}fi
${TAB}@if [ -z \$(SERVICE) ]; then \
${TAB}${TAB}echo "\$(BOLD)\$(RED)SERVICE was not set\$(RESET)"; \
${TAB}${TAB}ERROR=1; \
${TAB}fi
${TAB}@if [ -z \$(GCP_CREDENTIALS) ]; then \
${TAB}${TAB}echo "\$(BOLD)\$(RED)GCP_CREDENTIALS was not set.\$(RESET)"; \
${TAB}${TAB}ERROR=1; \
${TAB}fi
${TAB}@if [ ! -z \$\${ERROR} ] && [ \$\${ERROR} -eq 1 ]; then \
#${TAB}${TAB}echo "\$(BOLD)Example usage: \`GCP_CREDENTIALS=../account.json PROJECT=my_project SERVICE=vpc make plan\`\$(RESET)"; \
${TAB}${TAB}exit 1; \
${TAB}fi

prep: set-env ## Prepare a new workspace (environment) if needed, configure the tfstate backend, update any modules, and switch to the workspace
${TAB}@echo "\$(BOLD)Verifying that the GCS Storage bucket \$(GCS_BUCKET) for remote state exists\$(RESET)"
${TAB}@if ! gsutil ls -p \${PROJECT} gs://\${GCS_BUCKET} > /dev/null 2>&1 ; then \
${TAB}${TAB}echo "\$(BOLD)GCS_BUCKET bucket \$(GCS_BUCKET) was not found, create a new bucket with versioning enabled to store tfstate\$(RESET)"; \
${TAB}${TAB}exit 1; \
${TAB}else
${TAB}${TAB}echo "\$(BOLD)\$(GREEN)GCS_BUCKET bucket \$(GCS_BUCKET) exists\$(RESET)"; \
${TAB}fi
${TAB}@echo "\$(BOLD)Configuring the terraform backend\$(RESET)"
${TAB}@\$(TF_CMD) init \
${TAB}${TAB}-input=false \
${TAB}${TAB}-reconfigure \
${TAB}${TAB}-upgrade \
${TAB}${TAB}-verify-plugins=true \
${TAB}${TAB}-backend=true \
${TAB}${TAB}-backend-config="bucket=\${GCS_BUCKET}" \
${TAB}${TAB}-backend-config="credentials=\$(GCP_CREDENTIALS)" \
${TAB}${TAB}-backend-config="prefix=\${PREFIX}"

plan: prep ## Show what terraform thinks it will do
${TAB}@\$(TF_CMD) plan \
${TAB}${TAB}-input=false \
${TAB}${TAB}-refresh=true \

plan-target: prep ## Shows what a plan looks like for applying a specific resource
${TAB}@echo "\$(YELLOW)\$(BOLD)[INFO]   \$(RESET)"; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
${TAB}@read -p "PLAN target: " DATA && \
${TAB}${TAB}\$(TF_CMD) plan \
${TAB}${TAB}${TAB}-input=true \
${TAB}${TAB}${TAB}-refresh=true \
${TAB}${TAB}${TAB}-target=\$\$DATA

plan-destroy: prep ## Creates a destruction plan.
${TAB}@\$(TF_CMD) plan \
${TAB}${TAB}-input=false \
${TAB}${TAB}-refresh=true \
${TAB}${TAB}-destroy \

apply: prep ## Have terraform do the things. This will cost money.
${TAB}@\$(HELM_DEBU) \$(TF_CMD) apply \
${TAB}${TAB}-input=false \
${TAB}${TAB}-auto-approve \
${TAB}${TAB}-refresh=true \

destroy: prep ## Destroy the things
${TAB}@\$(TF_CMD) destroy \
${TAB}${TAB}-input=false \
${TAB}${TAB}-auto-approve \
${TAB}${TAB}-refresh=true \

destroy-target: prep ## Destroy a specific resource. Caution though, this destroys chained resources.
${TAB}@echo "\$(YELLOW)\$(BOLD)[INFO] Specifically destroy a piece of Terraform data.\$(RESET)"; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
${TAB}@read -p "Destroy target: " DATA && \
${TAB}${TAB}\$(TF_CMD) destroy \
${TAB}${TAB}-input=false \
${TAB}${TAB}-auto-approve \
${TAB}${TAB}-refresh=true \
${TAB}${TAB}-target=\$\$DATA

upgrade: prep ## Upgrade state to new terraform version
${TAB}@\$(TF_CMD) 0.13upgrade

output:
${TAB}@\$(TF_CMD) output

build:
${TAB}@gcloud builds submit --config=\${BUILD_CONFIG} \${BUILD_DIR}
MAKEFILE
}


cbmkfile () {
[[ -f Makefile  || -f makefile ]] && echo "Makefile exists" && exit 2 || \
  cat <<- CBMKFILE > Makefile
.PHONY: build test
#GCS_BUCKET="tf-state-73649"
PROJECT_ID=\$(shell gcloud config list --format 'value(core.project)' 2>/dev/null)
PROJECT_NUMBER=\$(shell gcloud projects describe \$(PROJECT_ID) --format='value(projectNumber)')
BUILD_CONFIG="cloudbuild.yaml"
BUILD_DIR=\$(.)

BOLD=\$(shell tput bold)
RED=\$(shell tput setaf 1)
GREEN=\$(shell tput setaf 2)
YELLOW=\$(shell tput setaf 3)
RESET=\$(shell tput sgr0)

test:
${TAB}${TAB}@echo "\$(BOLD)Verifying that the GCS Storage bucket \$(GCS_BUCKET) for remote state exists\$(RESET)"
${TAB}${TAB}@echo "\$(BOLD)Verifying the PROJECT_ID: \$(PROJECT_ID) \$(RESET)"
${TAB}${TAB}@echo "\$(BOLD)Verifying the PROJECT_NUMBER: \$(PROJECT_NUMBER) \$(RESET)"

build:
${TAB}${TAB}@gcloud builds submit --config=\${BUILD_CONFIG} \${BUILD_DIR}

update:
${TAB}${TAB}@echo "This feature will be available once we upgrade to tf 0.13""
CBMKFILE
}

cbuild () {
[[ -f cloudbuild.yaml ]] && echo "cloudbuild.yaml exists" && exit 2 || \
  cat <<- CBUILD > cloudbuild.yaml
# # To run the build manually do the following,
#      \$ \`gcloud builds submit --config=cloudbuild.yaml .\`
#

steps:
# Step 0
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args: [ '-c', "gcloud secrets versions access latest --secret=account --format='get(payload.data)' | tr '_-' '/+' | base64 --decode > account.json" ]

  # Step 1
- name: 'gcr.io/\$PROJECT_ID/terraform'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    #make plan
    #terraform plan
    make set-env
    make prep

timeout: 1200s
tags: ['terraform-gce']
CBUILD
}
# Functions   !-

echo "Line 272"

# Configure cloudbuild !+
[[ ! -d cloudbuild ]] && \
  mkdir cloudbuild && \
#  cd cloudbuild && \
#  cbmkfile && \
#  cd - && \
  cat <<- CLOUDBUILD > cloudbuild/cloudbuild.yaml
## In this directory, run the following command to build this builder.
## $ \`gcloud builds submit --config=cloudbuild.yaml .\`

steps:
- name: 'gcr.io/cloud-builders/wget'
  args: ["https://releases.hashicorp.com/terraform/\${_TERRAFORM_VERSION}/terraform_\${_TERRAFORM_VERSION}_linux_amd64.zip"]
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/\$PROJECT_ID/terraform:\${_TERRAFORM_VERSION}',
        '-t', 'gcr.io/\$PROJECT_ID/terraform',
        '--build-arg', 'TERRAFORM_VERSION=\${_TERRAFORM_VERSION}',
        '--build-arg', 'TERRAFORM_VERSION_SHA256SUM=\${_TERRAFORM_VERSION_SHA256SUM}',
        '.']
substitutions:
  _TERRAFORM_VERSION: 0.13.6
  _TERRAFORM_VERSION_SHA256SUM: 55f2db00b05675026be9c898bdd3e8230ff0c5c78dd12d743ca38032092abfc9

images:
- 'gcr.io/\$PROJECT_ID/terraform:latest'
- 'gcr.io/\$PROJECT_ID/terraform:\${_TERRAFORM_VERSION}'
tags: ['cloud-builders-community']
CLOUDBUILD

echo "Line 301"
[[ ! -f cloudbuild/Dockerfile ]] && \
  cat <<- DOCKERFILE > cloudbuild/dk
FROM alpine:3.9
#FROM gcr.io/google.com/cloudsdktool/cloud-sdk:alpine

ARG TERRAFORM_VERSION=0.13.6
ARG TERRAFORM_VERSION_SHA256SUM=55f2db00b05675026be9c898bdd3e8230ff0c5c78dd12d743ca38032092abfc9

COPY terraform_\${TERRAFORM_VERSION}_linux_amd64.zip .
RUN echo "\${TERRAFORM_VERSION_SHA256SUM}  terraform_\${TERRAFORM_VERSION}_linux_amd64.zip" > checksum && sha256sum -c checksum

RUN /usr/bin/unzip terraform_\${TERRAFORM_VERSION}_linux_amd64.zip

FROM centos:7
RUN printf '[google-cloud-sdk]\n\\
name=Google Cloud SDK\n\\
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64\n\\
enabled=1\n\\
gpgcheck=1\n\\
repo_gpgcheck=1\n\\
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg\n\\
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg\n'\\
    >> /etc/yum.repos.d/google-cloud-sdk.repo 
    #>> /etc/yum.repos.d/google-cloud-sdk.repo && \\
    #chmod 644 /etc/yum.repos.d/google-cloud-sdk.repo

RUN yum -y update && yum -y install ca-certificates && \\ 
    yum install -y epel-release git wget && \\
    yum install -y make && \\ 
    yum install -y google-cloud-sdk && \\
    yum install -y ansible && \\
    yum clean all && \\
    rm -rf /var/cache/yum && \\
    mkdir /root/.ssh && \\
    chmod 700 /root/.ssh 

COPY --from=0 terraform /usr/bin/terraform 

ENTRYPOINT ["/usr/bin/terraform"] 

DOCKERFILE

mv cloudbuild/dk cloudbuild/Dockerfile


echo "Line 349"
# Configure services !+ 
[[ ! -d project ]] && \
  mkdir project && \
  cd project && \
  mkfile project && \
  cbuild && \
  cd - 2>&1 1>/dev/null && \
  cat <<- PROJECT > project/main.tf
## ------------------------------------------------------------
##   BACKEND BLOCK
## ------------------------------------------------------------
#terraform {
#  backend "gcs" {
#    bucket = "${REMOTE_STATE_BUCKET}"
#    prefix = "${REMOTE_STATE_PREFIX}"
#  }
#}
#
## ------------------------------------------------------------
##   PROVIDER BLOCK
## ------------------------------------------------------------
#
#provider "google" {
#  credentials = file(var.credentials_path)
#  version = "~> 3.1"
#}
#
#provider "google-beta" {
#  credentials = file(var.credentials_path)
#  version = "~> 3.1"
#}
#
#provider "null" {
#  version = "~> 2.1"
#}
#
#provider "random" {
#  version = "~> 2.2"
#}
#
## ------------------------------------------------------------
##   TERRAFORM REMOTE STATE
## ------------------------------------------------------------
#
#data "google_project" "project" {
#  project_id = "${PROJECT_ID}"
#}
PROJECT

echo "Line 396"
[[ ! -f project/variables.tf ]] && \
  cat <<- VARIABLES > project/variables.tf
variable project_remote_state_bucket_name {
  type = string
  default = "${REMOTE_STATE_BUCKET}"
  description = "terraform state backend bucket"
}

variable credentials_path {
  type        = string
  default     = "${ACCOUNT_CREDENTIALS_PATH}"
  description = "Location of the credential file."
}

variable activate_apis {
  type = list
  default = [
    "compute.googleapis.com",
  ]
  description = "The list of apis to activate within the project	"
}

variable disable_dependent_services {
  type = bool
  default = true
  description = "Whether services that are enabled and which depend on this service should also be d    isabled when this service is destroyed."
}

#variable environment {
#  type = string
#  description = "The ID of a folder hosting this project"
#}

#variable environment_folder_id {
#  type = string
#  description = "The ID of a environment folder hosting this project"
#}

variable labels {
  description = "Map of labels for project."
  default = {
    "environment" = "dev"
    "managed_by"  = "terraform"
  }
}

variable project_home {
  description = "URI for the terraform state file"
  default = ".."
  type = string
}

variable project_name {
  description = "Name of the project."
  default     = "${PROJECT_NAME}"
}

variable random_project_id {
  description = "Enable random number to the end of the project."
  default     = true
}

variable region {
  description = "Default region"
}

variable service {
  description = "Then name og the GCP service instantiated by the module"
}

VARIABLES

echo "Line 472"
[[ ! -f project/outputs.tf ]] && \
  cat <<- OUTPUTS > project/outputs.tf
#output credentials_path {
#  value = var.credentials_path
#}
#
#output prefix {
#  value = "\${var.project_home}/\${var.service}"
#}
#
#output project_default_region {
#  value = var.region
#}
#
#output project_id {
#  value = data.google_project.project.project_id
#}
#
#output project_labels {
#  value = var.labels
#}
#
#output project_name {
#  value = data.google_project.project.project_name
#}
#
#output project_number {
#  value = module.project_factory.project_number
#}
#
#output remote_state_bucket_name {
#  value = var.remote_state_bucket_name
#}
OUTPUTS

echo "LINE 509"
[[ ! -f project/terraform.auto.tfvars.tf ]] && \
  cat <<- AUTO > project/terraform.auto.tfvars
credentials_path = "../account.json"

project_home = ".."

service = "project"

activate_apis = [
    "compute.googleapis.com",          // Required
    "billingbudgets.googleapis.com",   // Required
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "stackdriver.googleapis.com",
]

disable_dependent_services = true

labels = {
    "environment"   = ""
    "group"         = ""
    "managed_by"    = "terraform"
    "project_name"  = "${PROJECT_NAME}"
}

region = "${REGION}"
AUTO

echo "LINE 538"
[[ ! -d iam ]] && \
  mkdir iam && \
  cd iam && \
  mkfile iam && \
  cbuild && \
  cd - 2>&1 1>/dev/null && \
  cat <<- MAIN > iam/main.tf
terraform {
  backend "gcs" {}
}

provider "google" {
  credentials = file(var.credentials_path)
  version     = "\${GOOGLE_PROVIDER_VERSION}"
}

provider "google-beta" {
  credentials = file(var.credentials_path)
  version     = "\${GOOGLE_PROVIDER_VERSION}"
}

provider "null" {
  version = "~> 2.1"
}

locals {
  project_home = var.project_home
  this_service = "iam"
}

data "terraform_remote_state" "project" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "\${local.project_home}/project"
  }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "\${local.project_home}/\${local.this_service}"
  }
}

locals {
  svc_acct = "tf-project"
  svc_acct_email = google_service_account.\${svc_acct}.email
  project_id = data.terraform_remote_state.project.outputs.project_id
  svc_acct_def = "serviceAccount:\${local.svc_acct_email}"
}

resource "google_service_account" "tf_project" {
  account_id   = local.svc_acct
  display_name = local.svc_acct
  project      = local.project_id
}

module "project-iam-bindings" {
  source   = "terraform-google-modules/iam/google//modules/projects_iam"
  version = "~> 5.1.0"
  projects = ["\${data.terraform_remote_state.project.outputs.project_id}"]
  mode     = "additive"

  bindings = {
    "roles/owner" = [
      "\${local.svc_acct_def}",
      ]
  }
}
MAIN

echo "LINE 614"
[[ ! -f iam/variables.tf ]] && \
  cat <<- VARS > ./iam/variables.tf
variable credentials_path {
  type        = string
  default     = "${ACCOUNT_CREDENTIALS_PATH}"
  description = "Path to the .json file."
}

variable description {
  default = "Terraform-Deployed."
}

variable project_home {
  description = "URI for the terraform state file"
  type = string
}

variable remote_state_bucket_name {
  type = string
  default = "\${REMOTE_STATE_BUCKET}"
  description = "terraform state backend bucket"
}

variable service {
  type = string
  description = "The GCP service amnaged by this module"
}
VARS

echo "LINE 643"
[[ ! -f iam/outputs.tf ]] && \
  cat <<- OUTPUTS > ./iam/outputs.tf
//
// Service Outputs
//

output members {
  value = module.project-iam-bindings
}

output projects {
  value = module.project-iam-bindings
}

output roles {
  value = module.project-iam-bindings
}

output "service_account_mig_id" {
  value = google_service_account.instsvc0.id
}

output "service_account_mig_email" {
  value = google_service_account.instsvc0.email
}

output "service_account_mig_name" {
  value = google_service_account.instsvc0.name
}

output "service_account_mig_unique_id" {
  value = google_service_account.instsvc0.unique_id
}
OUTPUTS

echo "LINE 680"
[[ ! -f iam/terraform.auto.tfvars ]] && \
  cat <<- AUTO > ./iam/terraform.auto.tfvars
////
// Default org level variables required by all projects
////

credentials_path = "../account.json"

project_home = ".."

////
// Service specific variables
////
service = "iam"
AUTO


echo "LINE 698"
[[ ! -d vpc ]] && \
  mkdir vpc && \
  cd vpc && \
  mkfile vpc && \
  cbuild && \
  cd - 2>&1 1>/dev/null && \
  cat <<- MAIN > ./vpc/main.tf
// ------------------------------------------------------------
//   BACKEND BLOCK
// ------------------------------------------------------------
terraform {
  backend "gcs" {}
}

# ------------------------------------------------------------
#   PROVIDER BLOCK
# ------------------------------------------------------------

provider "google" {
  credentials = file(var.credentials_path)
  version     = "~> 3.38.0"
}

provider "google-beta" {
  credentials = file(var.credentials_path)
  version     = "~> 3.38.0"
}

provider "null" {
  version = "~> 2.1"
}

# ------------------------------------------------------------
#   TERRAFORM REMOTE STATE
# ------------------------------------------------------------
locals {
  #bucket       = data.terraform_remote_state.project.outputs.remote_state_bucket_name
  bucket            = var.remote_state_bucket_name
  credentials_path  = var.credentials_path
  project_home      = var.project_home
  this_service      = var.service
}

data "terraform_remote_state" "project" {
  backend = "gcs"
  config = {
    bucket      = local.bucket
    credentials = local.credentials_path
    prefix      = "\${local.project_home}/project"
  }
}

data "terraform_remote_state" "shared-vpc" {
  backend = "gcs"
  config = {
    bucket      = local.bucket
    credentials = local.credentials_path
    prefix      = "\${local.project_home}/\${local.this_service}"
  }
}

////
// local definitions
////

# ------------------------------------------------------------
#   MAIN BLOCK
# ------------------------------------------------------------

#data "google_compute_network" "shared_vpc" {
#  name    = var.network_name
#  project = var.shared_vpc_project_id
#}

#data "google_compute_router" "nyu-ng-usc1" {
#  name = "nyu-ng-usc1"
#  network = data.google_compute_network.shared_vpc.self_link
#  project = var.shared_vpc_project_id
#  region  = "us-central1"
#}

#output "nyu-ng-usc1_id" {
#  value = data.google_compute_router.nyu-ng-usc1.id
#}

#output "nyu-ng-usc1_self_link" {
#  value = data.google_compute_router.nyu-ng-usc1.self_link
#}

#data "google_compute_router" "nyu-cl2" {
#  name = "nyu-cl2"
#  network = data.google_compute_network.shared_vpc.self_link
#  project = var.shared_vpc_project_id
#  region  = "us-east4"
#}

#output "nyu-cl2_id" {
#  value = data.google_compute_router.nyu-cl2.id
#}
#
#output "nyu-cl2-self_link" {
#  value = data.google_compute_router.nyu-cl2.self_link
#}

#resource "google_compute_router" "fj5-lb-default" {
#  name    = "fj5-lb-http-router"
#  network = data.google_compute_network.shared_vpc.self_link
#  project = var.shared_vpc_project_id
#  region  = "us-central1"
#}
##output default_router_self_link {
##  value = google_compute_router.fj5-lb-usc1-default.self_link
##}
MAIN


echo "LINE 815"
[[ ! -f vpc/outputs.tf ]] && \
  cat <<- OUTPUTS > ./vpc/outputs.tf
output network_name {
  value = module.vpc.network_name
}

output network_self_name {
  value = module.vpc.network_name
}

output network_self_link {
  value = module.vpc.network_self_link
}

output route_names {
  value = module.vpc.route_names
}

output subnets_flow_logs {
  value = module.vpc.subnets_flow_logs
}

output subnets_ips {
  value = module.vpc.subnets_ips
}

output subnets_names {
  value = module.vpc.subnets_names
}

output subnets_private_access {
  value = module.vpc.subnets_private_access
}

output subnets_regions {
  value = module.vpc.subnets_regions
}

output subnets_self_links {
  value = module.vpc.subnets_self_links
}

output subnetworks_self_links {
  value = module.vpc.subnets_self_links
}

// router outputs
output default_router_id {
  value = google_compute_router.default.id
}

output default_router_name {
  value = trimprefix(google_compute_router.default.id, "projects/\${data.terraform_remote_state.project.outputs.project_id}/regions/us-central1/routers/")
}

output default_router_creation_timestamp {
  value = google_compute_router.default.creation_timestamp
}

output default_router_self_link {
  value = google_compute_router.default.self_link
}


echo "LINE 880"
OUTPUTS
[[ ! -f vpc/variables.tf ]] && \
  cat <<- VARIABLES > ./vpc/variables.tf
//
// Project variables
//

variable credentials_path {
  type        = string
  default     = "../account.json"
  description = "Path to the .json file."
}

variable network_name {
  type = string
  description = "The network name from the Shared VPC"
}

variable project_home {
  type = string
  description = "Path to thhe project files. The statefile prefix has the form project_home/this-service"
}

variable remote_state_bucket_name {
  type = string
  default = "\$REMOTE_STATE_BUCKET"
  description = "terraform state backend bucket"
}

variable service {
  type = string
  description = "The GCP service managed by this module"
}
VARIABLES

echo "LINE 916"
[[ ! -f vpc/terraform.auto.tfvars ]] && \
  cat <<- AUTO > ./vpc/terraform.auto.tfvars
//
// Default org level variables required by all projects
////

credentials_path = "../account.json"

project_home = ".."

service = "vpc"

network_name            = "\${NETWORK}"

remote_state_bucket_name = "\${REMOTE_STATE_BUCKET}"

AUTO
# Configure services !-

echo "LINE 936"
## Set tf creds a secret
RESULT=$(gcloud secrets create account  --replication-policy automatic --data-file $ACCOUNT 2>&1)
REPLY=$(echo $RESULT | sed 's/.*\(account\).*/\1/')
[[ $REPLY != "account" ]] && printf "Account credential secret not set.\nExiting..." && exit 9 || \
  rm -f $ACCOUNT



echo "After secrets"
## Set up cloudbuild to run tf
