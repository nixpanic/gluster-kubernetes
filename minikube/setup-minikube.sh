#!/bin/sh
#
# Work in progress script to test single-node Gluster storage in a container.
#
# Assumptions:
# - minimal Fedora installation
#
# Steps to execute:
# - install dependencies/tools
# - download and configure minikube
# - attach a disk for Gluster bricks
# - run 'gk-deploy --single-node'
#
# TODO:
# - ansiblize?
# - current minikube VM does not have device-mapper/thin provisioning -> FAILS
#
# Author: Niels de Vos <ndevos@redhat.com>
#

# fail when an error occurs
set -e

# run verbose
set -x

setenforce 0
sed -i s/=enforcing/=permissive/ /etc/selinux/config

yum -y install docker libvirt-daemon-kvm libvirt-daemon-config-network libvirt-client git
sed s/native.cgroupdriver=systemd/native.cgroupdriver=cgroupfs/ /usr/lib/systemd/system/docker.service > /etc/systemd/system/docker.service
systemctl daemon-reload
systemctl enable docker
systemctl start docker
systemctl enable libvirtd
systemctl start libvirtd

virsh pool-list default || virsh pool-create-as --default --type dir --target /var/lib/libvirt/images
virsh vol-create-as default minikube-gluster.qcow2 --capacity 1024G --format qcow2 --prealloc-metadata

mkdir $HOME/bin || true
[ -x $HOME/bin/minikube ] || curl -Lo $HOME/bin/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && chmod +x $HOME/bin/minikube
[ -x $HOME/bin/kubectl ] || curl -Lo $HOME/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x $HOME/bin/kubectl
[ -x $HOME/bin/docker-machine-driver-kvm2 ] || curl -Lo $HOME/bin/docker-machine-driver-kvm2 https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2 && chmod +x $HOME/bin/docker-machine-driver-kvm2

export MINIKUBE_WANTUPDATENOTIFICATION=false
export MINIKUBE_WANTREPORTERRORPROMPT=false
export MINIKUBE_HOME=$HOME
export CHANGE_MINIKUBE_NONE_USER=true
mkdir $HOME/.kube || true
touch $HOME/.kube/config

export KUBECONFIG=$HOME/.kube/config
#$HOME/bin/minikube start --vm-driver=none --network-plugin=cni
$HOME/bin/minikube start --vm-driver=kvm2 --network-plugin=cni

# this for loop waits until kubectl can access the api server that Minikube has created
for i in {1..150}; do # timeout for 5 minutes
  kubectl get po &> /dev/null
  if [ $? -ne 1 ]; then
    break
  fi
  sleep 2
done

# kubectl commands are now able to interact with Minikube cluster

virsh attach-disk minikube /var/lib/libvirt/images/minikube-gluster.qcow2 vdb --persistent --targetbus virtio
# online/live adding does not seem to work
minikube stop
minikube start

git clone https://github.com/gluster/gluster-kubernetes
pushd gluster-kubernetes/deploy

MINIKUBE_IP=$(minikube ip)
MINIKUBE_HOSTNAME=$(minikube ssh hostname)

cat << EOF > topology.json
{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                "${MINIKUBE_HOSTNAME}"
              ],
              "storage": [
                "${MINIKUBE_IP}"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/vdb"
          ]
        }
      ]
    }
  ]
}
EOF

./gk-deploy --yes --verbose --single-node --no-object --deploy-gluster --cli=kubectl topology.json

