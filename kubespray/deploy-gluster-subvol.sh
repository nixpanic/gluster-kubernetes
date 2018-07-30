#!/bin/sh
#
# Install and configure a StorageClass based on the gluster-subvol FlexVolume
# provisioner.
#

# Install dependencies
yum -y install ansible jq

# get the provisioner
git clone https://github.com/gluster/gluster-subvol.git
pushd gluster-subvol

# Installation on the host
pushd glfs-subvol
ansible-playbook -i localhost install_plugin.yml
popd

# might need to enable --enable-controller-attach-detach kubelet option?
