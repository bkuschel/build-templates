#
# Copyright 2018 The Knative Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# A simple script to create or validate credentials to allow pushing
# built images to ECR.
#
# This script assumes the following environment:
#
# 1. `ibmcloud`, 'kubectl` installed and in $PATH.
#
# 2. User authenticated ibmcloud session (ie. `ibmcloud login`)
#
# 3. The authenticated user has to have the Administrator platform role 
#    for the container-registry service for the regions in which the service ID
#    will have access to the registry. Read README.MD for details on service ID's policy.
#
# The script should warn if any of these preconditions cannot be met.
#
# Once all arguments are validated, this script will create a kubernetes
# secret with the appropriate metadata for usage by build steps, accessible
# by a service account named "builder" (by default).
#
##
## Validate environment.
##
param(
    [string]$namespace = "",
    [string]$KUBE_SA= "builder"
)

function checkBinary([string]$command) {
    $Result = Get-Command $command
    if ($Result.ExitCode) {
        exit 1
    }
}

checkBinary ibmcloud
checkBinary kubectl

[string]$KUBECTL_FLAGS= if ([string]::IsNullOrEmpty($namespace)) { $namespace } else { "-n $1" }

kubectl $KUBECTL_FLAGS get sa | Out-Null
if ($lastexitcode) {
    Write-Host "Unable to read Kubernetes service accounts with 'kubectl $KUBECTL_FLAGS get sa'."
    exit 1
}

##
## Begin ...
##

[string]$IBMCLOUD_SERVICEID_NAME = if (Test-Path Env:IBMCLOUD_SERVICEID_NAME) { $Env:IBMCLOUD_SERVICEID_NAME } else { "knative-builder" }

# See if secrets are already loaded. If not, add them.
if ((kubectl $KUBECTL_FLAGS get -o jsonpath='{.secrets[?(@.name=="icr-creds")].name}' sa $KUBE_SA 2>&1) -eq 'icr-creds' ) {
    Write-Host "Found serviceAccount '$KUBE_SA' with access to 'icr-creds'"
    if ((kubectl  $KUBECTL_FLAGS get -o jsonpath={.type} secrets icr-creds 2>&1) -eq 'kubernetes.io/basic-auth' ) {
        Write-Host "Secrets set up already, exiting"
        exit
    }
}

ibmcloud iam service-id $IBMCLOUD_SERVICEID_NAME 2>&1 | Out-Null

if ($lastexitcode) {
    Write-Host "Could not find $IBMCLOUD_SERVICEID_NAME, creating..."
    ibmcloud iam service-id-create $IBMCLOUD_SERVICEID_NAME -d "Knative Builder" | Out-Null
} else {
    Write-Host "Using existing service account $IBMCLOUD_SERVICEID_NAME"
}

Write-Host "Creating policy defined in icr/policy.json for service ID $IBMCLOUD_SERVICEID_NAME ..."
ibmcloud iam service-policy-create $IBMCLOUD_SERVICEID_NAME --file icr/policy.json
if ($lastexitcode) {
    exit 2
}

# Create the API Key key for the service account.
Write-Host "Creating API Key called $IBMCLOUD_SERVICEID_NAME for service ID $IBMCLOUD_SERVICEID_NAME ..."
ibmcloud iam service-api-key-create $IBMCLOUD_SERVICEID_NAME $IBMCLOUD_SERVICEID_NAME --file knative-builder-key.json
if ($lastexitcode) {
    exit 2
}

@" 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $KUBE_SA
secrets:
- name: icr-creds
---
apiVersion: v1
kind: Secret
metadata:
  name: icr-creds
  annotations:
    build.knative.dev/docker-0: registry.ng.bluemix.net
    build.knative.dev/docker-1: registry.bluemix.net
    build.knative.dev/docker-2: registry.eu-de.bluemix.net
    build.knative.dev/docker-3: registry.eu-gb.bluemix.net
    build.knative.dev/docker-4: registry.au-syd.bluemix.net
type: kubernetes.io/basic-auth
data:
  username: $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('iamapikey')))
  password: $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($(Get-Content -Path knative-builder-key.json | ConvertFrom-Json).apikey)))
"@ | kubectl $KUBECTL_FLAGS apply -f -

$EXIT=$lastexitcode

Remove-Item knative-builder-key.json

exit $EXIT
