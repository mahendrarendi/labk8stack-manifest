# LabK8stack deployment

This repository deploys LabK8stack with Helm and Argo CD. It contains separate
`development` and `production` values and Argo CD projects. The CloudNativePG
(CNPG) operator, PostgreSQL clusters, storage, backups, and Secrets are managed
separately from this chart.

## Layout

| Path | Purpose |
| --- | --- |
| `templates/` | Application, migration, cleanup, network, RBAC, and admission resources |
| `environments/` | Development and production values |
| `argocd/` | Environment projects and manual-sync Applications |
| `scripts/validate.sh` | Helm lint and render checks used locally and in CI |
| `scripts/bootstrap-production-secrets.sh` | One-time namespace and Secret provisioning for initial production integration |

## Prerequisites

- Kubernetes 1.30+ with `ValidatingAdmissionPolicy` support. The namespace
  guard is enabled by default. Check with `kubectl api-resources | grep
  validatingadmissionpolicies`.
- Argo CD permitted to manage the chart's cluster-scoped RBAC and admission
  resources.
- Healthy, separate development and production CNPG clusters, with tested
  backup and restore procedures.
- An application image in a registry. Pin application releases by immutable
  image digest. A separate challenge image is optional for the initial website
  deployment; see **Challenge workload image** below.
- HTTPS ingress and TLS certificates; session cookies use the `Secure` flag.
- A Secret manager or synchronization controller. Never commit Secret values
  or database URLs to this repository.

## Database and Secrets

Each environment must use a separate CNPG cluster and database. The production
values target the existing `labk8stack-pgcluster` in `cnpg-system`; the
development values still target a future development cluster. The chart
expects two Secrets **in the application namespace**:

| Secret | Required keys | Purpose |
| --- | --- | --- |
| `app.configSecretName` | `SECRET_KEY`, `LAB_APP_IMAGE`, `LAB_APP_GOOD_TAGS` | Session signing and lab image configuration |
| `database.appSecretName` | `uri` by default; production uses `fqdn-uri` | PostgreSQL connection URI |

When CNPG shares the application namespace, the chart can use CNPG's
`<clusterName>-app` Secret. For production, mirror the CNPG application Secret
into namespace `labk8stack` with the same name. Its `fqdn-uri` key points to
`labk8stack-pgcluster-rw.cnpg-system.svc.cluster.local` and is read directly by
the chart. Pods cannot read Secrets in another namespace. Configure the Secret
manager to update the local copy when credentials rotate, and restart
long-running application Pods to pick up the new environment value.

### Challenge workload image

`LAB_APP_IMAGE` is the image created inside each learner's lab namespace. It
is not the LabK8stack platform image. A purpose-built sample workload is
archived outside the two active project directories. It does not need to be
built before the platform website can be deployed. For an initial integration
test, set:

```env
LAB_APP_IMAGE=registry.k8s.io/echoserver:1.10
LAB_APP_GOOD_TAGS=1.10,latest
```

This generic image is enough to start the platform and test some lab flows.
The OOM, readiness-probe, and port-env challenges will not show their intended
real-cluster symptoms with it. Build and publish the sample workload (or an
equivalent image with the required behavior) before opening all challenges to
users.

For a separate database namespace, configure its NetworkPolicy alongside
CNPG to allow TCP 5432 from application Pods. This chart installs a CNPG
ingress policy only when CNPG is in the application namespace. Preserve the
operator's required access if the database namespace uses default-deny.

Configure CNPG backup and retention with the database deployment. Restore a
backup into a separate cluster and run an application smoke test against it.
Alert on backup failures, CNPG health, application readiness, migration
failures, and cleanup failures.

## Security boundary

The application creates one namespace per user and challenge. Kubernetes RBAC
cannot restrict namespace creation or deletion by name prefix. This chart
installs a `ValidatingAdmissionPolicy` and binding that deny the application
ServiceAccount's namespace and lab resource writes outside
`app.namespacePrefix`. Argo CD installs the policy before the workload using
a sync wave; the policy fails closed.

This guard reduces provisioner risk, but a shared Kubernetes cluster is not a
hard tenant boundary. The application retains cluster-scoped permissions and
can impersonate the challenge `lab-runner` ServiceAccount. Run untrusted public
labs in a dedicated cluster, or add an independently administered policy layer
before sharing a cluster with sensitive workloads. Restrict who may change
ClusterRoles, admission policies, and Argo CD projects.

Development and production use separate namespace prefixes, databases, and
Argo CD projects. Assign different Argo CD roles and repository review rules
to each project. Both environments still target one cluster in the supplied
manifests; use separate clusters when stronger isolation or independent
availability is required.

## Availability and migrations

The web Deployment defaults to two replicas, rolling updates, a
PodDisruptionBudget with one available replica, and preferred spread across
nodes. At least two schedulable nodes are needed for node maintenance without
an application interruption. Readiness and liveness probes are included.
Database availability depends on the CNPG and storage design.

The migration Job runs before web updates. Schema changes must be backward
compatible with the currently running application during a rolling release.
Review migrations before promotion; reverting an image does not reverse a
database migration.

## Release workflow

The sequence below applies once the development database is available. For an
initial production-only integration, follow **Configure and install** instead
and treat that first deployment as a controlled smoke test.

1. Build and test the application in its source repository. Its CI runs tests
   against PostgreSQL and publishes an image. Record the immutable digest.
2. Update `environments/development/values.yaml` with the image repository and
   digest. Open a reviewed pull request and run `bash scripts/validate.sh`.
   Merge, then sync the development Argo CD Application.
3. Smoke test login, namespace creation, challenge verification, reset, and
   cleanup against development and its CNPG cluster.
4. Copy the **same tested image digest** to
   `environments/production/values.yaml`. Review the production pull request.
   Pin the production Argo CD `targetRevision` to the approved release tag or
   commit, apply the updated Application resource, then sync production after
   approval. The Application resource is not self-managed by Argo CD.
5. Check migration, rollout, readiness, logs, CNPG health, and backup status.
   If the release fails, evaluate migration compatibility before rolling back
   the Argo CD revision.

The supplied Argo CD Applications use manual sync. Git changes appear as
`OutOfSync` until synced. Development follows `main`; production has a release
tag or commit placeholder. Argo CD renders the Helm chart and manages its
Kubernetes resources. Do not also run `helm upgrade` for the same release.

## Configure and install

1. Wait for `labk8stack-pgcluster` to report three ready instances. Confirm
   the `labk8stack-pgcluster-app` Secret and its `fqdn-uri` key exist.
2. Configure scheduled backups outside this chart and perform a restore test.
   Three database instances on the same NFS storage do not replace an
   independent backup. Choose the backup method supported by your CNPG and
   storage versions; do not assume NFS CSI supports VolumeSnapshots. Check the
   installed resources with `kubectl -n cnpg-system get scheduledbackups,backups`
   and `kubectl get volumesnapshotclasses`. If VolumeSnapshotClass is not
   installed, configure object-store backup with the CNPG backup plugin or
   another supported method before production use.
3. Create namespace `labk8stack`. Synchronize the CNPG application Secret into
   it and create `labk8stack-config` with `SECRET_KEY`, `LAB_APP_IMAGE`, and
   `LAB_APP_GOOD_TAGS`. Use your Secret manager for rotation. The one-time copy
   below is suitable only for initial integration testing. The easiest way to
   perform it is:

   ```bash
   bash scripts/bootstrap-production-secrets.sh
   ```

   The script generates a random session key, uses the public echoserver as
   the initial lab image, skips Secrets that already exist, and never prints
   Secret values. To use a different lab image, set `LAB_APP_IMAGE` and
   `LAB_APP_GOOD_TAGS` in the shell before running it. Its CNPG Secret copy
   does not follow credential rotation.

   For manual provisioning, the equivalent commands are:

   ```bash
   kubectl -n cnpg-system get cluster labk8stack-pgcluster
   kubectl -n cnpg-system get secret labk8stack-pgcluster-app -o json \
     | jq -e '.data["fqdn-uri"] != null' >/dev/null
   kubectl create namespace labk8stack
   kubectl -n cnpg-system get secret labk8stack-pgcluster-app -o json \
     | jq '{apiVersion: .apiVersion, kind: .kind, metadata: {name: .metadata.name, namespace: "labk8stack"}, type: .type, data: .data}' \
     | kubectl create -f -
   kubectl -n labk8stack create secret generic labk8stack-config \
     --from-env-file=/secure/path/labk8stack-config.env
   ```

   Store the env file outside the Git repository with restricted permissions.
   It must contain a random `SECRET_KEY` and valid challenge image values.
   The public image above is suitable for the initial website deployment.
   Generate the session key with `openssl rand -hex 32`.
   The manual Secret copy does not follow CNPG credential rotation.
4. Verify the configured `repoURL` points to your actual GitHub repository.
   Verify the production image digest and pinned Git revision, then set the
   ingress host, class, and TLS Secret. Create DNS and the TLS
   Secret before exposing the site. Verify that any database NetworkPolicy
   permits application Pods to reach port 5432.
5. Run `bash scripts/validate.sh`, apply `argocd/project.yaml` and
   `argocd/production.application.yaml`, then sync production manually. Deploy
   development only after its own CNPG cluster and Secrets are ready.

For a standalone chart check:

```bash
helm lint . -f environments/development/values.yaml \
  --set-string image.repository=REGISTRY/labk8stack \
  --set-string image.digest=sha256:IMAGE_DIGEST
```

The environment files intentionally contain placeholders. The manifests are
not deployable until you supply your registry, digest, Git URL, CNPG clusters,
Secrets, ingress, and TLS settings.

## Verification

After syncing production, inspect the rollout, guard, and database:

```bash
kubectl -n labk8stack rollout status deployment/labk8stack
kubectl -n labk8stack get pods,jobs,cronjobs,pdb
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding | grep labk8stack
kubectl -n cnpg-system get cluster labk8stack-pgcluster
```

Use a dedicated test account to create and solve a lab, then verify cleanup
removes expired namespaces. Monitor namespace count and resource usage. Test a
rejected out-of-prefix write in a non-production cluster after chart changes.
