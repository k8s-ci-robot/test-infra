#!/usr/bin/env bash
# Copyright 2020 The Kubernetes Authors.
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

set -o errexit

readonly OUTPUT="$(dirname $0)/k8s-staging-sig-storage.yaml"

# Repos for which cloud image builds are working.
readonly REPOS=(
    kubernetes-csi/csi-driver-host-path
    kubernetes-csi/csi-driver-smb
    kubernetes-csi/csi-test
    kubernetes-csi/external-attacher
    kubernetes-csi/external-health-monitor
    kubernetes-csi/external-provisioner
    kubernetes-csi/external-resizer
    kubernetes-csi/external-snapshotter
    kubernetes-csi/livenessprobe
    kubernetes-csi/node-driver-registrar
    kubernetes-csi/csi-driver-nfs
    kubernetes-csi/csi-driver-iscsi
    kubernetes-sigs/sig-storage-local-static-provisioner
    kubernetes-sigs/nfs-ganesha-server-and-external-provisioner
    kubernetes-sigs/nfs-subdir-external-provisioner
)

# Repos which should eventually enable cloud image builds but currently
# don't.
readonly BROKEN_REPOS=(
    kubernetes-csi/csi-proxy
    kubernetes-sigs/container-object-storage-interface-controller
    kubernetes-sigs/container-object-storage-interface-provisioner-sidecar
    kubernetes-sigs/container-object-storage-interface-csi-adapter
)

cat >"${OUTPUT}" <<EOF
# Automatically generated by k8s-staging-sig-storage-gen.sh.

postsubmits:
EOF

for repo in "${REPOS[@]}" "${BROKEN_REPOS[@]}"; do
    IFS=/ read -r org repo <<<"${repo}"
    cat >>"${OUTPUT}" <<EOF
  ${org}/${repo}:
    - name: post-${repo}-push-images
      rerun_auth_config:
        github_team_slugs:
          - org: kubernetes
            slug: release-managers
          - org: kubernetes
            slug: test-infra-admins
          - org: kubernetes
            slug: sig-storage-image-build-admins
      cluster: k8s-infra-prow-build-trusted
      annotations:
        testgrid-dashboards: sig-storage-image-build
      decorate: true
      branches:
        # For publishing canary images.
        - ^master$
        - ^release-
        # For publishing tagged images. Those will only get built once, i.e.
        # existing images are not getting overwritten. A new tag must be set to
        # trigger another image build. Images are only built for tags that follow
        # the semver format (regex from https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string).
        - ^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
      spec:
        serviceAccountName: gcb-builder
        containers:
          - image: gcr.io/k8s-testimages/image-builder:v20210302-aa40187
            command:
              - /run.sh
            args:
              # this is the project GCB will run in, which is the same as the GCR
              # images are pushed to.
              - --project=k8s-staging-sig-storage
              # This is the same as above, but with -gcb appended.
              - --scratch-bucket=gs://k8s-staging-sig-storage-gcb
              - --env-passthrough=PULL_BASE_REF
              - .
EOF
done

cat >>"${OUTPUT}" <<EOF

# Canary images are used by some Prow jobs to ensure that the upcoming releases
# of the sidecars work together. We don't promote those canary images.
# To avoid getting them evicted from the staging area, we have to rebuild
# them periodically. One additional benefit is that build errors show up
# in the sig-storage-image-build *before* tagging a release.
#
# Periodic jobs are currently only specified for the "master" branch
# which produces the "canary" images. While other branches
# could produce release-x.y-canary images, we don't use those.
periodics:
EOF

for repo in "${REPOS[@]}"; do
    IFS=/ read -r org repo <<<"${repo}"
cat >>"${OUTPUT}" <<EOF
- name: canary-${repo}-push-images
  cluster: k8s-infra-prow-build-trusted
  annotations:
    testgrid-dashboards: sig-storage-image-build
  decorate: true
  interval: 168h # one week
  extra_refs:
    # This also becomes the current directory for run.sh and thus
    # the cloud image build.
    - org: kubernetes-csi
      repo: ${repo}
      base_ref: master
  spec:
    serviceAccountName: gcb-builder
    containers:
      - image: gcr.io/k8s-testimages/image-builder:v20210302-aa40187
        command:
          - /run.sh
        env:
        # We need to emulate a pull job for the cloud build to work the same
        # way as it usually does.
        - name: PULL_BASE_REF
          value: master
        args:
          # this is the project GCB will run in, which is the same as the GCR
          # images are pushed to.
          - --project=k8s-staging-sig-storage
          # This is the same as above, but with -gcb appended.
          - --scratch-bucket=gs://k8s-staging-sig-storage-gcb
          - --env-passthrough=PULL_BASE_REF
          - .
EOF
done
