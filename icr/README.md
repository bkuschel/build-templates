# IBM Container Registry Helper 

The scripts provision (or verifies) an IBM Cloud service ID with
permissions as secified by the policy.json file. The user must be logged into 
IBM Cloud with a user that has the `Administrator` role assigned to the 
`container-registry` service for the region(s). See `iamcloud iam user-policy-create` 

By default, the following resources will be provisioned:

* An IBM Cloud Service ID named `knative-builder` with appropriate permissions.
* A Kubernetes service account (named `builder` by default) with secrets to
  enable pushing to IBM Cloud using the `knative-builder`'s credentials.

The default policy.json file allow images to be built and pushed into the registry of 
any region and registry namepsace. (see @policy.json)
It is possible to restrict the policy to a region and a registry namespace as follows, multiple
specific regions' attributes can be added to the `resources` array.

```json
{
    "roles": [
        {
            "role_id": "crn:v1:bluemix:public:iam::::serviceRole:Writer"
        }
    ],
    "resources": [
        {
            "attributes": [
                {
                    "name": "serviceName",
                    "value": "container-registry"
                },
                {
                    "name": "region",
                    "value": "us-east"
                },
                {
                    "name": "resourceType",
                    "value": "namespace"
                },
                {
                    "name": "resource",
                    "value": "mynamespace"
                }
            ]
        }
    ]
}
```

To use, simply add a `serviceAccountName: builder` entry to your build definition

```yaml:
apiVersion: build.knative.dev/v1alpha1
kind: Build
metadata:
  name: mybuild
spec:
  serviceAccountName: builder
  source: ...
  template: ...
```

## Usage

Should be run from the repository root directory.

```shell
# Usage assumes that the user has IAM Owner permissions for the project.
icr/helper.(sh|ps1)
```

Optionally, `helper.(sh|ps1)` accepts two positional arguments to specify
the namespace and kubernetes service account used:

```shell
icr/helper.(sh|ps1) $MY_KUBE_NAMESPACE builder-serviceaccount
```

This will output a log of operations performed or skipped:

```
Could not find knative-builder, creating...
Creating service ID knative-builder bound to current account as kuschel@ca.ibm.com...
OK
Service ID knative-builder is created successfully

Name          knative-builder
Description   Knative Builder
CRN           crn:v1:bluemix:public:iam-identity::a/790c0808c946b9e15cc2e63013fded9d::serviceid:ServiceId-14483a83-4079-4103-9c1e-1879834feddb
Bound To      crn:v1:bluemix:public:::a/790c0808c946b9e15cc2e63013fded9d:::
Version       1-6684c1b5255d0c300b25b4268a97fd9c
Locked        false
UUID          ServiceId-14483a83-4079-4103-9c1e-1879834feddb
Creating policy under current account for service ID knative-builder as kuschel@ca.ibm.com...
OK
Service policy is successfully created


Policy ID:   e167c8ff-5e29-4d7a-a671-f50868a4e2e9
Version:     1-9004ae95ef74d0b1c6e5adf9bdd35a4b
Roles:       Writer
Resources:
             Service Name       container-registry
             Service Instance
             Region
             Resource Type
             Resource



Creating API key knative-builder of service knative-builder as kuschel@ca.ibm.com...
OK
Service API key knative-builder is created
Successfully save API key information to knative-builder-key.json
serviceaccount/builder created
secret/icr-creds created
```