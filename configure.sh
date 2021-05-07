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
CREDENTIALS_PATH="./account.json"
PROJECT_HOME=".."
GOOGLE_PROVIDER_VERSION="3.65.0"
GOOGLE_BETA_PROVIDER_VERSION="3.65.0"
NULL_PROVIDER_VERSION="2.1"
NETWORK_MODULE_VERSION="2.5"
RANDOM_PROVIDER_VERSION="2.2"

echo "Enter project_name:" && \
read PROJECT_NAME && \

echo "Enter project_id:" && \
read PROJECT_ID  && \

CONFIGPATH="${HOME}/.config/gcloud/configurations/config_${PROJECT_NAME}"

[[ ! -f ${HOME}/.config/gcloud/configurations/config_fj5-dev ]] && \
  echo "Enter default zone: " && \
  read ZONE && \
  echo "Enter GCP email address: " && \
  read GCP_EMAIL && \

  REGION=$(echo $ZONE | sed 's/.\{2\}$//') && \
  project_config || \
  # If configuration exits pull value from it.
  #PROJECT_ID=$(grep project $CONFIGPATH | sed s/'project = '//) && \
  #PROJECT_NAME=$(gcloud projects list --filter=${PROJECT_NAME} --format='value(name)') && \
  ZONE=$(grep zone $CONFIGPATH | sed s/'zone = '//) && \
  #REGION=$(echo $ZONE |  awk -F '=' '{  print $2 }' | sed 's/.\{2\}$//') && \
  REGION=$(echo $ZONE |  sed 's/.\{2\}$//') && \
  
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

# enable apis
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable secretmanager.googleapis.com

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

# Functions   !+
mkfile () {
[[ -f Makefile  || -f makefile ]] && echo "Makefile exists" && exit 2 || \

  echo "Lk9ORVNIRUxMOgouU0hFTEwgOj0gL3Vzci9iaW4vYmFzaAouUEhPTlk6IGFwcGx5IHRmLWFkcHBseSBkZXN0cm95IHRmLWRlc3Ryb3kgZGVzdHJveS10YXJnZXQgcGxhbi1kZXN0cm95IHBsYW4gdGYtcGxhbiBwbGFuLXRhcmdldCBwcmVwIG91dHB1dCB0Zi1vdXRwdXQgCkJVQ0tFVD0idGYtJHtQUk9KRUNUX0lEfSIKQlVJTERfQ09ORklHPSJjbG91ZGJ1aWxkLnlhbWwiCkJVSUxEX0RJUj0iLiIKUFJPSkVDVD0kKFBST0pFQ1RfSUQpClBST0pFQ1RfTlVNQkVSPSQoc2hlbGwgZ2Nsb3VkIHByb2plY3RzIGRlc2NyaWJlICQoUFJPSkVDVF9JRCkgLS1mb3JtYXQ9J3ZhbHVlKHByb2plY3ROdW1iZXIpJykKU0VSVklDRT0kKHNoZWxsIGJhc2VuYW1lICR7UFdEfSkKQ1VSUkVOVF9GT0xERVI9JChzaGVsbCBiYXNlbmFtZSAiJCQocHdkKSIpCkJPTEQ9JChzaGVsbCB0cHV0IGJvbGQpClJFRD0kKHNoZWxsIHRwdXQgc2V0YWYgMSkKR1JFRU49JChzaGVsbCB0cHV0IHNldGFmIDIpCllFTExPVz0kKHNoZWxsIHRwdXQgc2V0YWYgMykKUkVTRVQ9JChzaGVsbCB0cHV0IHNncjApClRGX0NNRD0idGVycmFmb3JtIgpIRUxNX0RFQlVHPSJIRUxNX0RFQlVHPTEiCgpoZWxwOgoJQGdyZXAgLUUgJ15bYS16QS1aXy1dKzouKj8jIyAuKiQkJyAkKE1BS0VGSUxFX0xJU1QpIHwgc29ydCB8IGF3ayAnQkVHSU4ge0ZTID0gIjouKj8jIyAifTsge3ByaW50ZiAiXDAzM1szNm0lLTMwc1wwMzNbMG0gJXNcbiIsICQkMSwgJCQyfScKCnNldC1lbnY6CglAaWYgWyAteiAkKFBST0pFQ1QpIF07IHRoZW4gXAoJCWVjaG8gIiQoQk9MRCkkKFJFRClQUk9KRUNUIHdhcyBub3Qgc2V0JChSRVNFVCkiOyBcCgkJRVJST1I9MTsgXAoJZmkKCUBpZiBbIC16ICQoU0VSVklDRSkgXTsgdGhlbiBcCgkJZWNobyAiJChCT0xEKSQoUkVEKVNFUlZJQ0Ugd2FzIG5vdCBzZXQkKFJFU0VUKSI7IFwKCQlFUlJPUj0xOyBcCglmaQoJQGlmIFsgISAteiAkJHtFUlJPUn0gXSAmJiBbICQke0VSUk9SfSAtZXEgMSBdOyB0aGVuIFwKCQllY2hvICIkKEJPTEQpRXhhbXBsZSB1c2FnZTogXGBDUkVERU5USUFMUz0uLi9jcmVkZW50aWFscy5qc29uIFBST0pFQ1Q9bXlfcHJvamVjdCBTRVJWSUNFPXByb2plY3QgbWFrZSBwbGFuXGAkKFJFU0VUKSI7IFwKCQlleGl0IDE7IFwKCWZpCgpwcmVwOiBzZXQtZW52ICMjIFByZXBhcmUgYSBuZXcgd29ya3NwYWNlIChlbnZpcm9ubWVudCkgaWYgbmVlZGVkLCBjb25maWd1cmUgdGhlIHRmc3RhdGUgYmFja2VuZCwgdXBkYXRlIGFueSBtb2R1bGVzLCBhbmQgc3dpdGNoIHRvIHRoZSB3b3Jrc3BhY2UKCUBlY2hvICIkKEJPTEQpVmVyaWZ5aW5nIHRoYXQgdGhlIEdDUyBTdG9yYWdlIGJ1Y2tldCAkKEJVQ0tFVCkgZm9yIHJlbW90ZSBzdGF0ZSBleGlzdHMkKFJFU0VUKSIgCgkjIFN0aWxsIG5lZWQgdG8gdGVzdCBpZiAkKEJVQ0tFVCkgZXhpc3RzCglAZWNobyAiJChCT0xEKUNvbmZpZ3VyaW5nIHRoZSB0ZXJyYWZvcm0gYmFja2VuZCQoUkVTRVQpIgoJQCQoVEZfQ01EKSBpbml0IFwKCQktaW5wdXQ9ZmFsc2UgXAoJCS1yZWNvbmZpZ3VyZSBcCgkJLXVwZ3JhZGUgXAoJCS12ZXJpZnktcGx1Z2lucz10cnVlIFwKCQktYmFja2VuZD10cnVlIAoKdGYtcGxhbjogcHJlcCAjIyBTaG93IHdoYXQgdGVycmFmb3JtIHRoaW5rcyBpdCB3aWxsIGRvCglAJChURl9DTUQpIHBsYW4gXAoJCS1pbnB1dD1mYWxzZSBcCgkJLXJlZnJlc2g9dHJ1ZSAKCnBsYW4tdGFyZ2V0OiBwcmVwICMjIFNob3dzIHdoYXQgYSBwbGFuIGxvb2tzIGxpa2UgZm9yIGFwcGx5aW5nIGEgc3BlY2lmaWMgcmVzb3VyY2UKCUBlY2hvICIkKFlFTExPVykkKEJPTEQpW0lORk9dICAgJChSRVNFVCkiOyBlY2hvICJFeGFtcGxlIHRvIHR5cGUgZm9yIHRoZSBmb2xsb3dpbmcgcXVlc3Rpb246IG1vZHVsZS5yZHMuYXdzX3JvdXRlNTNfcmVjb3JkLnJkcy1tYXN0ZXIiCglAcmVhZCAtcCAiUExBTiB0YXJnZXQ6ICIgREFUQSAmJiBcCgkJJChURl9DTUQpIHBsYW4gXAoJCQktaW5wdXQ9dHJ1ZSBcCgkJCS1yZWZyZXNoPXRydWUgXAoJCQktdGFyZ2V0PSQkREFUQQoKcGxhbi1kZXN0cm95OiBwcmVwICMjIENyZWF0ZXMgYSBkZXN0cnVjdGlvbiBwbGFuLgoJQCQoVEZfQ01EKSBwbGFuIFwKCQktaW5wdXQ9ZmFsc2UgXAoJCS1yZWZyZXNoPXRydWUgXAoJCS1kZXN0cm95IAoKdGYtYXBwbHk6IHByZXAgIyMgSGF2ZSB0ZXJyYWZvcm0gZG8gdGhlIHRoaW5ncy4gVGhpcyB3aWxsIGNvc3QgbW9uZXkuCglAJChURl9DTUQpIGFwcGx5IFwKCQktaW5wdXQ9ZmFsc2UgXAoJCS1hdXRvLWFwcHJvdmUgXAoJCS1yZWZyZXNoPXRydWUgCgp0Zi1kZXN0cm95OiBwcmVwICMjIERlc3Ryb3kgdGhlIHRoaW5ncwoJQCQoVEZfQ01EKSBkZXN0cm95IFwKCQktaW5wdXQ9ZmFsc2UgXAoJCS1hdXRvLWFwcHJvdmUgXAoJCS1yZWZyZXNoPXRydWUgCgpkZXN0cm95LXRhcmdldDogcHJlcCAjIyBEZXN0cm95IGEgc3BlY2lmaWMgcmVzb3VyY2UuIENhdXRpb24gdGhvdWdoLCB0aGlzIGRlc3Ryb3lzIGNoYWluZWQgcmVzb3VyY2VzLgoJQGVjaG8gIiQoWUVMTE9XKSQoQk9MRClbSU5GT10gU3BlY2lmaWNhbGx5IGRlc3Ryb3kgYSBwaWVjZSBvZiBUZXJyYWZvcm0gZGF0YS4kKFJFU0VUKSI7IGVjaG8gIkV4YW1wbGUgdG8gdHlwZSBmb3IgdGhlIGZvbGxvd2luZyBxdWVzdGlvbjogbW9kdWxlLnJkcy5hd3Nfcm91dGU1M19yZWNvcmQucmRzLW1hc3RlciIKCUByZWFkIC1wICJEZXN0cm95IHRhcmdldDogIiBEQVRBICYmIFwKCQkkKFRGX0NNRCkgZGVzdHJveSBcCgkJLWlucHV0PWZhbHNlIFwKCQktYXV0by1hcHByb3ZlIFwKCQktcmVmcmVzaD10cnVlIFwKCQktdGFyZ2V0PSQkREFUQQoKdGYtb3V0cHV0OiBwcmVwCglAJChURl9DTUQpIG91dHB1dAoKIyMjCiMgIGJ1aWxkIHRhcmdldHMgY2FsbCBjbG91ZCBidWlsZCB3aGljaCBydW5zIHRhcnJhZm9ybSB0YXJnZXRzCiMjIwoKcGxhbjoKCUBnY2xvdWQgYnVpbGRzIHN1Ym1pdCAtLXN1YnN0aXR1dGlvbnM9X0JVSUxEU1RBVEU9InRmLXBsYW4iIC0tY29uZmlnPWNsb3VkYnVpbGQueWFtbCAuCgphcHBseToKCUBnY2xvdWQgYnVpbGRzIHN1Ym1pdCAtLXN1YnN0aXR1dGlvbnM9X0JVSUxEU1RBVEU9InRmLWFwcGx5IiAtLWNvbmZpZz1jbG91ZGJ1aWxkLnlhbWwgLgoKZGVzdHJveToKCUBnY2xvdWQgYnVpbGRzIHN1Ym1pdCAtLXN1YnN0aXR1dGlvbnM9X0JVSUxEU1RBVEU9InRmLWRlc3Ryb3kiIC0tY29uZmlnPWNsb3VkYnVpbGQueWFtbCAuCgppbml0OgoJQGdjbG91ZCBidWlsZHMgc3VibWl0IC0tc3Vic3RpdHV0aW9ucz1fQlVJTERTVEFURT0icHJlcCIgLS1jb25maWc9Y2xvdWRidWlsZC55YW1sIC4KCm91dHB1dDoKCUBnY2xvdWQgYnVpbGRzIHN1Ym1pdCAtLXN1YnN0aXR1dGlvbnM9X0JVSUxEU1RBVEU9InRmLW91dHB1dCIgLS1jb25maWc9Y2xvdWRidWlsZC55YW1sIC4KCg==" | base64 --decode > Makefile

}

cbmkfile () {
[[ -f Makefile  || -f makefile ]] && echo "Makefile exists" && exit 2 || \
echo "LlBIT05ZOiBidWlsZCB0ZXN0ClBST0pFQ1RfTlVNQkVSPSQoc2hlbGwgZ2Nsb3VkIHByb2plY3RzIGRlc2NyaWJlICQoUFJPSkVDVF9JRCkgLS1mb3JtYXQ9J3ZhbHVlKHByb2plY3ROdW1iZXIpJykKQlVJTERfQ09ORklHPSJjbG91ZGJ1aWxkLnlhbWwiCkJVSUxEX0RJUj0kKC4pCgpCT0xEPSQoc2hlbGwgdHB1dCBib2xkKQpSRUQ9JChzaGVsbCB0cHV0IHNldGFmIDEpCkdSRUVOPSQoc2hlbGwgdHB1dCBzZXRhZiAyKQpZRUxMT1c9JChzaGVsbCB0cHV0IHNldGFmIDMpClJFU0VUPSQoc2hlbGwgdHB1dCBzZ3IwKQoKdGVzdDoKCQlAZWNobyAiJChCT0xEKVZlcmlmeWluZyB0aGF0IHRoZSBHQ1MgU3RvcmFnZSBidWNrZXQgJChCVUNLRVQpIGZvciByZW1vdGUgc3RhdGUgZXhpc3RzICQoUkVTRVQpIgoJCUBlY2hvICIkKEJPTEQpVmVyaWZ5aW5nIHRoZSBQUk9KRUNUX0lEOiAkKFBST0pFQ1RfSUQpICQoUkVTRVQpIgoJCUBlY2hvICIkKEJPTEQpVmVyaWZ5aW5nIHRoZSBQUk9KRUNUX05VTUJFUjogJChQUk9KRUNUX05VTUJFUikgJChSRVNFVCkiCgpidWlsZDoKCQlAZ2Nsb3VkIGJ1aWxkcyBzdWJtaXQgLS1jb25maWc9JHtCVUlMRF9DT05GSUd9ICR7QlVJTERfRElSfQo=" | base64 --decode > Makefile
}

cloudbuild () {
[[ -f cloudbuild.yaml ]] && echo "cloudbuild.yaml exists" && exit 2 || \
  cat <<- CBUILD > cloudbuild.yaml
# # To run the build manually do the following,
#      \$ \`gcloud builds submit --config=cloudbuild.yaml .\`
#

steps:
# Step 0
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:  
  - '-c' 
  - |
    gcloud secrets versions access latest --secret=account --format='get(payload.data)' \
     | tr '_-' '/+' | base64 --decode > account.json

# Step 1
- name: 'gcr.io/\$PROJECT_ID/terraform'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    [[ -d .terraform ]] && rm -rf .terraform
    [[ -L account.json ]] && unlink account.json
    make \${_BUILDSTATE} 
  env:
    - TERM=xterm
    - PROJECT_ID=\${PROJECT_ID}
    - SERVICE=\${_SERVICE}

substitutions:
  _SERVICE: \${SERVICE}
  _BUILDSTATE: not

timeout: 1200s
tags: ['terraform-gce']
CBUILD
}
# Functions   !-

echo "Line 272"

# Configure cloudbuild !+
[[ ! -d cloudbuild ]] && \
  mkdir cloudbuild && \
  cd cloudbuild && \
  cbmkfile && \
  cd - 2>&1 1>/dev/null && \
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
  cat <<- DOCKERFILE > cloudbuild/Dockerfile
FROM alpine:3.9

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


echo "Line 345"
# Configure services !+ 
[[ ! -d project ]] && \
  mkdir project && \
  cd project && \
  mkfile project && \
  cloudbuild && \
  cd - 2>&1 1>/dev/null && \
  cat <<- PROJECTMAIN > project/main.tf
## ------------------------------------------------------------
##   BACKEND BLOCK
## ------------------------------------------------------------
terraform {
  backend "gcs" {
    bucket = "${REMOTE_STATE_BUCKET}"
    prefix = "/project"
    credentials = "${ACCOUNT}"
  }
}

# ------------------------------------------------------------
#   PROVIDER BLOCK
# ------------------------------------------------------------

provider "google" {
  credentials = file(var.credentials_path)
  version = "~> ${GOOGLE_PROVIDER_VERSION}"
}

provider "google-beta" {
  credentials = file(var.credentials_path)
  version = "~> ${GOOGLE_BETA_PROVIDER_VERSION}"
}

provider "null" {
  version = "~> ${NULL_PROVIDER_VERSION}"
}

provider "random" {
  version = "~> ${RANDOM_PROVIDER_VERSION}"
}

// ------------------------------------------------------------
//   TERRAFORM REMOTE STATE
// ------------------------------------------------------------
data "terraform_remote_state" "project" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "/project"
  }
}


data "google_project" "project" {
  project_id = "${PROJECT_ID}"
}

PROJECTMAIN

echo "Line 396"
[[ ! -f project/variables.tf ]] && \
  cat <<- PROJECTVARIABLES > project/variables.tf
variable remote_state_bucket_name {
  type = string
  default = "${REMOTE_STATE_BUCKET}"
  description = "terraform state backend bucket"
}

variable credentials_path {
  type        = string
  default     = "${CREDENTIALS_PATH}"
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

variable labels {
  description = "Map of labels for project."
  default = {
    "environment" = ""
    "managed_by"  = "terraform"
    "project"     = "${PROJECT_NAME}"
  }
}

variable project_home {
  description = "URI for the terraform state file"
  default = "${PROJECT_HOME}"
  type = string
}

variable project_name {
  description = "Name of the project."
  default     = "${PROJECT_NAME}"
}

variable project_number {
  description = "Name of the project."
  default     = "${PROJECT_NUMBER}"
}

variable region {
  description = "Default region"
}

variable service {
  description = "Then name og the GCP service instantiated by the module"
}
PROJECTVARIABLES

echo "Line 451"

[[ ! -f project/outputs.tf ]] && \
  cat <<- PROJECTOUTPUTS > project/outputs.tf
output credentials_path {
  value = var.credentials_path
}

output prefix {
  value = "${REMOTE_STATE_PREFIX}"
}

output project_default_region {
  value = var.region
}

output project_id {
  value = data.google_project.project.project_id
}

output project_labels {
  value = var.labels
}

output project_name {
  value = var.project_name
}

output project_number {
  value = var.project_number
}

output remote_state_bucket_name {
  value = var.remote_state_bucket_name
}
PROJECTOUTPUTS

echo "LINE 509"
[[ ! -f project/terraform.auto.tfvars.tf ]] && \
  cat <<- AUTO > project/terraform.auto.tfvars
credentials_path = "./account.json"

project_home = "${PROJECT_HOME}"

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
  cloudbuild && \
  cd - 2>&1 1>/dev/null && \
  cat <<- IAMMAIN > iam/main.tf
// ------------------------------------------------------------
//   BACKEND BLOCK
// ------------------------------------------------------------
terraform {
  backend "gcs" {
    bucket = "${REMOTE_STATE_BUCKET}"
    prefix = "/iam"
    credentials = "account.json"
  }
}

// ------------------------------------------------------------
//   PROVIDER BLOCK
// ------------------------------------------------------------
provider "google" {
  credentials = file(var.credentials_path)
  version     = "${GOOGLE_PROVIDER_VERSION}"
}

provider "google-beta" {
  credentials = file(var.credentials_path)
  version     = "${GOOGLE_PROVIDER_VERSION}"
}

provider "null" {
  version = "~> 2.1"
}

locals {
  project_home = var.project_home
  this_service = "iam"
}

// ------------------------------------------------------------
//   TERRAFORM REMOTE STATE
// ------------------------------------------------------------
data "terraform_remote_state" "project" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "/project"
  }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "/iam"
  }
}

locals {
  svc_acct = "tf-project"
  svc_acct_email = "google_service_account.\${local.svc_acct}.email"
  project_id = data.terraform_remote_state.project.outputs.project_id
  svc_acct_def = "serviceAccount:\${local.svc_acct_email}"
}

#resource "google_service_account" "tf_project" {
#  account_id   = local.svc_acct
#  display_name = local.svc_acct
#  project      = local.project_id
#}

module "project-iam-bindings" {
  source   = "terraform-google-modules/iam/google//modules/projects_iam"
  version = "~> 5.1.0"
  projects = [data.terraform_remote_state.project.outputs.project_id,]
  mode     = "additive"

  bindings = {
    #"roles/owner" = [
    #  "\${local.svc_acct_def}",
    #  ]
  }
}
IAMMAIN

echo "LINE 614"
[[ ! -f iam/variables.tf ]] && \
  cat <<- IAMVARS > ./iam/variables.tf
variable credentials_path {
  type        = string
  default     = "${CREDENTIALS_PATH}"
  description = "Path to the .json file."
}

variable description {
  default = "Terraform-Deployed."
}

variable project_home {
  type        = string
  default     = "${PROJECT_HOME}"
  description = "URI for the terraform state file"
}

variable project_name {
  type        = string
  default     = "${PROJECT_NAME}"
  description = "URI for the terraform state file"
}

variable project_number {
  type        = string
  default     = "${PROJECT_NUMBER}"
  description = "URI for the terraform state file"
}
variable remote_state_bucket_name {
  type = string
  default = "${REMOTE_STATE_BUCKET}"
  description = "terraform state backend bucket"
}

variable service {
  type = string
  description = "The GCP service amnaged by this module"
}
IAMVARS

echo "LINE 643"
[[ ! -f iam/outputs.tf ]] && \
  cat <<- IAMOUTPUTS > ./iam/outputs.tf
//
// Service Outputs
//

#output members {
#  value = module.project-iam-bindings
#}

#output projects {
#  value = module.project-iam-bindings
#}

#output roles {
#  value = module.project-iam-bindings
#}

IAMOUTPUTS

echo "LINE 677"

[[ ! -f iam/terraform.auto.tfvars ]] && \
  cat <<- IAMAUTO > ./iam/terraform.auto.tfvars
////
// Default org level variables required by all projects
////

credentials_path = "${ACCOUNT}"

project_home = "${PROJECT_HOME}"

////
// Service specific variables
////
service = "iam"
IAMAUTO

echo "LINE 690"

[[ ! -d vpc ]] && \
  mkdir vpc && \
  cd vpc && \
  mkfile vpc && \
  cloudbuild && \
  cd - 2>&1 1>/dev/null && \
  cat <<- VPCMAIN > ./vpc/main.tf
// ------------------------------------------------------------
//   BACKEND BLOCK
// ------------------------------------------------------------
// Values for the terraform block are provided by the Makefile
terraform {
  backend "gcs" {
    bucket = "${REMOTE_STATE_BUCKET}"
    prefix = "/vpc"
    credentials = "${ACCOUNT}"
  }
}

// ------------------------------------------------------------
//   PROVIDER BLOCK
// ------------------------------------------------------------

provider "google" {
  credentials = file(var.credentials_path)
  version     = "~> ${GOOGLE_PROVIDER_VERSION}"
}

provider "google-beta" {
  credentials = file(var.credentials_path)
  version     = "~> ${GOOGLE_BETA_PROVIDER_VERSION}"
}

provider "null" {
  version = "~> ${NULL_PROVIDER_VERSION}"
}

// ------------------------------------------------------------
//   TERRAFORM REMOTE STATE
// ------------------------------------------------------------
locals {
  project_home = var.project_home
  this_service      = "vpc"
}

data "terraform_remote_state" "project" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "/project"
  }
}

data "terraform_remote_state" "compute" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "/compute"
  }
}

data "terraform_remote_state" "vpc" {
  backend = "gcs"
  config = {
    bucket      = var.remote_state_bucket_name
    credentials = var.credentials_path
    prefix      = "/vpc"
  }
}

////
// local definitions
////
locals {
  region                 = data.terraform_remote_state.project.outputs.project_default_region
  subnet_01              = "\${data.terraform_remote_state.project.outputs.project_name}-subnet-01"
  subnet_01_ip           = "192.168.1.0/24"
  subnet_01_secondary_ip = "192.168.2.0/24"
  subnet_01_description  = "ssh access"
  subnet_02              = "\${data.terraform_remote_state.project.outputs.project_name}-subnet-02"
  subnet_02_ip           = "10.10.20.0/24"
  subnet_02_description  = "Subnet description"
  subnet_03              = "\${data.terraform_remote_state.project.outputs.project_name}-subnet-03"
  subnet_03_ip           = "10.10.30.0/24"
  subnet_03_description  = "Subnet description"
  subnet_03_region       = data.terraform_remote_state.project.outputs.project_default_region

  router_name = "\${module.vpc.network_name}-router"
  project_id  = data.terraform_remote_state.project.outputs.project_id
}

# ------------------------------------------------------------
#   MAIN BLOCK
# ------------------------------------------------------------

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> ${NETWORK_MODULE_VERSION}"

  project_id   = data.terraform_remote_state.project.outputs.project_id
  network_name = "\${data.terraform_remote_state.project.outputs.project_name}-\${var.network_suffix}"
  routing_mode = var.routing_mode
  delete_default_internet_gateway_routes = false

  subnets = [
    {
      subnet_name           = local.subnet_01
      subnet_ip             = local.subnet_01_ip
      subnet_region         = data.terraform_remote_state.project.outputs.project_default_region
      subnet_private_access = true
      subnet_flow_logs      = var.subnet_flow_logs
      description           = local.subnet_01_description
    },
    {
      subnet_name           = local.subnet_02
      subnet_ip             = local.subnet_02_ip
      subnet_region         = data.terraform_remote_state.project.outputs.project_default_region
      subnet_private_access = true
      subnet_flow_logs      = var.subnet_flow_logs
      description           = local.subnet_02_description
    },
    {
      subnet_name               = local.subnet_03
      subnet_ip                 = local.subnet_03_ip
      subnet_region             = data.terraform_remote_state.project.outputs.project_default_region
      subnet_private_access     = true
      subnet_flow_logs          = var.subnet_flow_logs
      subnet_flow_logs_interval = "INTERVAL_10_MIN"
      subnet_flow_logs_sampling = 0.7
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
    },
  ]

  secondary_ranges = {
      subnet_01 = [
          {
              range_name    = "subnet_01_secondary_ip"
              ip_cidr_range = local.subnet_01_secondary_ip
          },
      ]

      subnet_02 = []
      subnet_03 = []
  }

  routes = [
    {
      name              = "tf-egress-internet"
      description       = "route through the IGW to access the internet"
      destination_range = "0.0.0.0/0"
      tags              = "egress-inet"
      next_hop_internet = true
    },
    // Example route to instance proxy
    //{
    //  name = "app-proxy"
    //  description = "route through proxy to reach app"
    //  destination_range = local.subnet_01_ip
    //  tags              = "app-proxy"
    //  next_hop_instance = "app-proxy-instance"
    //  next_hop_instance_zone = "\${local.subnet_03_region}-a"
    //},
  ]
}

locals {
  loadbalancer_addresses = ["130.211.0.0/22","35.191.0.0/16"]
  iap_addresses          = ["35.235.240.0/20"]

  allow-ingress-iap = {
    description          = "Allow ssh INGRESS"
    direction            = "INGRESS"
    action               = "allow"
    ranges               = local.iap_addresses
    use_service_accounts = false # if \`true\` targets/sources expect list of instances SA, if false - list of tags
    targets              = null  # target_service_accounts or target_tags depends on \`use_service_accounts\` value
    sources              = null  # source_service_accounts or source_tags depends on \`use_service_accounts\` value
    rules = [{
     protocol = "tcp"
      ports    = null
      },
      {
        protocol = "udp"
        ports    = null
    }]
    extra_attributes = {
      disabled = false
      priority = 95
    }
  } // !- allow-ingress-iap

  allow-ingress-iap-ssh = {
    description          = "Allow ssh INGRESS"
    direction            = "INGRESS"
    action               = "allow"
    ranges               = local.iap_addresses
    use_service_accounts = false # if \`true\` targets/sources expect list of instances SA, if false - list of tags
    targets              = null  # target_service_accounts or target_tags depends on \`use_service_accounts\` value
    sources              = null  # source_service_accounts or source_tags depends on \`use_service_accounts\` value
    rules = [{
      protocol = "tcp"
      ports    = ["22"]
      },
      {
        protocol = "udp"
        ports    = null
    }]

    extra_attributes = {
      disabled = false
      priority = 95
    }
  } // !- allow-ingress-iap-ssh

  allow-ingress-80-443-8080 = {
    description          = "Allow all INGRESS to port 6534-6566"
    direction            = "INGRESS"
    action               = "allow"
    ranges               = local.loadbalancer_addresses # source or destination ranges (depends on \`direction\`)
    use_service_accounts = false # if \`true\` targets/sources expect list of instances SA, if false - list of tags
    targets              = null  # target_service_accounts or target_tags depends on \`use_service_accounts\` value
    sources              = null  # source_service_accounts or source_tags depends on \`use_service_accounts\` value
    rules = [{
      protocol = "tcp"
      ports    = ["80","443","8080"]
      },
      {
        protocol = "udp"
        ports    = null
    }]
    extra_attributes = {
      disabled = false
      priority = 95
    },
  } // !- allow-ingress-80-443-8080
} // !- locals


module "firewall-submodule" {
  source  = "terraform-google-modules/network/google//modules/fabric-net-firewall"
  version = "~> ${NETWORK_MODULE_VERSION}"

  project_id              = data.terraform_remote_state.project.outputs.project_id
  network                 = module.vpc.network_name
  internal_ranges_enabled = true
  internal_ranges         = module.vpc.subnets_ips

  internal_allow = [
    {
      protocol = "icmp"
    },
    {
      protocol = "tcp",
      # all ports open if 'ports' key isn't specified
    },
    {
      protocol = "udp"
      # all ports open if 'ports' key isn't specified
    },
  ]
  #custom_rules = local.custom_rules
  custom_rules = {
    #allow-ingress-22          = local.allow-ingress-22
    allow-ingress-iap-ssh     = local.allow-ingress-iap-ssh
    allow-ingress-80-443-8080 = local.allow-ingress-80-443-8080
  }
}

VPCMAIN

echo "LINE 815"

[[ ! -f vpc/outputs.tf ]] && \
  cat <<- VPCOUTPUTS > ./vpc/outputs.tf
//
// VPC Outputs
//

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
VPCOUTPUTS

[[ ! -f vpc/variables.tf ]] && \
  cat <<- VPCVARIABLES > ./vpc/variables.tf
variable credentials_path {
  type    = string
  default = "${CREDENTIALS_PATH}"
}

variable remote_state_bucket_name {
  type        = string
  default     = "${REMOTE_STATE_BUCKET}"
}

variable service {
  type        = string
  default     = "vpc"
  description = "The GCP service managed by this module"
}

variable network_suffix {
  description = "Name of the VPC."
}

variable project_home {
  description = "URI for the terraform state file"
  type = string
}

variable routing_mode {
  description = "Routing mode. GLOBAL or REGIONAL"
  default     = "GLOBAL"
}

variable subnet_name {
  description = "Name of the subnet."
}

variable subnet_ip {
  description = "Subnet IP CIDR."
}

variable subnet_region {
  description = "Region subnet lives in."
}

variable subnet_private_access {
  default = "true"
}

variable subnet_flow_logs {
  default = "true"
}
VPCVARIABLES

echo "LINE 916"

[[ ! -f vpc/terraform.auto.tfvars ]] && \
  cat <<- VPCAUTO > ./vpc/terraform.auto.tfvars
//
// Default org level variables required by all projects
////

credentials_path         = "${CREDENTIALS_PATH}"

project_home             = "${PROJECT_HOME}"

network_name             = "${NETWORK}"

service                  = "vpc"

network_suffix           = "net"

remote_state_bucket_name = "${REMOTE_STATE_BUCKET}"

routing_mode             = "GLOBAL"

subnet_flow_logs         = true

subnet_ip                = "192.168.0.100/24"

subnet_name              = "subnet-01"

subnet_private_access    = true

subnet_region            = "us-central1"
VPCAUTO
# Configure services !-

echo "LINE 936"
## Set tf creds a secret
RESULT=$(gcloud secrets create account  --replication-policy automatic --data-file $ACCOUNT 2>&1)
REPLY=$(echo $RESULT | sed 's/.*\(account\).*/\1/')
[[ $REPLY != "account" ]] && printf "Account credential secret not set.\nExiting..." && exit 9 || \
  rm -f $ACCOUNT



echo "End"
