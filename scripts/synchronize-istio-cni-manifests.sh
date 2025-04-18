#!/usr/bin/env bash
# This script helps to create a PR to update the manifests
set -euxo pipefail
IFS=$'\n\t'

COMMIT="1.24.3"
CURRENT_VERSION="1-24" 
NEW_VERSION="1-24" # Must be a release

SRC_DIR=${SRC_DIR:=/tmp/istio-cni}
BRANCH=${BRANCH:=istio-cni-${COMMIT?}}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MANIFESTS_DIR=$(dirname $SCRIPT_DIR)

ISTIO_OLD=$MANIFESTS_DIR/common/istio-cni-${CURRENT_VERSION}
ISTIO_NEW=$MANIFESTS_DIR/common/istio-cni-${NEW_VERSION}

if [ ! -d "$ISTIO_NEW" ]; then
cp -a $ISTIO_OLD $ISTIO_NEW
fi 

echo "Creating branch: ${BRANCH}"

if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: You have uncommitted changes"
fi
if [ `git branch --list $BRANCH` ]
then
   echo "WARNING: Branch $BRANCH already exists."
fi

# Create the branch in the manifests repository
if ! git show-ref --verify --quiet refs/heads/$BRANCH; then
    git checkout -b $BRANCH
else
    echo "Branch $BRANCH already exists."
fi
echo "Checking out in $SRC_DIR to $COMMIT..."

# Checkout the istio repository
if [ ! -d "$SRC_DIR" ]; then
mkdir -p $SRC_DIR
fi
cd $SRC_DIR
if [ ! -d "istio-${COMMIT}" ]; then
    wget "https://github.com/istio/istio/releases/download/${COMMIT}/istio-${COMMIT}-linux-amd64.tar.gz"
    tar xvfz istio-${COMMIT}-linux-amd64.tar.gz
fi

ISTIOCTL=$SRC_DIR/istio-${COMMIT}/bin/istioctl
cd $ISTIO_NEW

$ISTIOCTL manifest generate -f profile.yaml -f profile-overlay.yaml --set components.cni.enabled=true --set components.cni.namespace=kube-system > dump.yaml
./split-istio-packages -f dump.yaml
mv $ISTIO_NEW/crd.yaml $ISTIO_NEW/istio-crds/base
mv $ISTIO_NEW/install.yaml $ISTIO_NEW/istio-install/base
mv $ISTIO_NEW/cluster-local-gateway.yaml $ISTIO_NEW/cluster-local-gateway/base
rm dump.yaml

if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: You have uncommitted changes"
fi

# Update README.md to synchronize with the upgraded Istio version
echo "Updating README..."
SRC_TXT="\[.*\](https://github.com/istio/istio/releases/tag/.*)"
DST_TXT="\[$COMMIT\](https://github.com/istio/istio/releases/tag/$COMMIT)"

sed -i "s|$SRC_TXT|$DST_TXT|g" "${MANIFESTS_DIR}"/README.md

#Synchronize the updated directory names with other files
find "$MANIFESTS_DIR" -type f -not -path '*/.git/*' -exec sed -i "s/istio-cni-${CURRENT_VERSION}/istio-cni-${NEW_VERSION}/g" {} +

echo "Committing the changes..."
cd "$MANIFESTS_DIR"
rm -rf $ISTIO_OLD
git add .
git commit -s -m "Upgrade istio-cni to v.${COMMIT}"