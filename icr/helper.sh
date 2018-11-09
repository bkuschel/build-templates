#!/bin/bash
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

checkBinary() {
    if ! which $1 >&/dev/null; then
        echo "Unable to locate $1, please ensure it is installed and on your \$PATH."
        exit 1
    fi
}

checkBinary ibmcloud
checkBinary kubectl
readonly KUBECTL_FLAGS="${1:+ -n $1}"

if ! kubectl $KUBECTL_FLAGS get sa >& /dev/null; then
    echo "Unable to read Kubernetes service accounts with 'kubectl $KUBECTL_FLAGS get sa'."
    exit 1
fi

readonly KUBE_SA=${2:-"builder"}


##
## Begin ...
##

: ${IBMCLOUD_SERVICEID_NAME:=knative-builder}

# Supress stderr, as many of the check queries will print extra output
# if the resources are not present. Keep stderr on FD 3 to allow
# printing output from explicit create commands.
exec 3>&2
exec 2>/dev/null

# See if secrets are already loaded. If not, add them.
if [[ $(kubectl $KUBECTL_FLAGS get -o jsonpath='{.secrets[?(@.name=="icr-creds")].name}' sa $KUBE_SA) == 'icr-creds' ]]; then
    echo "Found serviceAccount '$KUBE_SA' with access to 'icr-creds'"
    if [[ $(kubectl $KUBECTL_FLAGS get -o jsonpath={.type} secrets icr-creds) == 'kubernetes.io/basic-auth' ]]; then
	echo "Secrets set up already, exiting"
	exit 0
    fi
fi

if ibmcloud iam service-id $IBMCLOUD_SERVICEID_NAME >&/dev/null; then
    echo "Using existing service account $IBMCLOUD_SERVICEID_NAME"
else
    echo "Could not find $IBMCLOUD_SERVICEID_NAME, creating..."
    ibmcloud iam service-id-create $IBMCLOUD_SERVICEID_NAME -d "Knative Builder"
fi

echo "Creating policy defined in icr/policy.json for service ID $IBMCLOUD_SERVICEID_NAME ..."
ibmcloud iam service-policy-create $IBMCLOUD_SERVICEID_NAME --file icr/policy.json 2>&3 || exit 2

# Create the API Key key for the service account.
echo "Creating API Key called $IBMCLOUD_SERVICEID_NAME for service ID $IBMCLOUD_SERVICEID_NAME ..."
ibmcloud iam service-api-key-create $IBMCLOUD_SERVICEID_NAME $IBMCLOUD_SERVICEID_NAME --file knative-builder-key.json 2>&3 || exit 2


cat <<EOF | kubectl $KUBECTL_FLAGS apply -f - 2>&3
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
  username: $(echo -n "iamapikey" | openssl base64 -a -A) # Should be aWFtYXBpa2V5
  password: $(cat knative-builder-key.json | sed 's/[[:space:]]//g' | grep -Po '(?<="apikey":")(.*?)(?=",)' | openssl base64 -a -A )
EOF

readonly EXIT=$?

rm knative-builder-key.json

exit $EXIT
