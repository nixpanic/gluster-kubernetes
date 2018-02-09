#!/bin/sh

yum -y install git ansible python-netaddr

hostnamectl set-hostname node1
swapoff -a
sed -i '/swap/d' /etc/fstab

mkdir $HOME/bin || true
[ -x $HOME/bin/kubectl ] || curl -Lo $HOME/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x $HOME/bin/kubectl

git clone https://github.com/kubernetes-incubator/kubespray
pushd kubespray

# kubespray needs python-jinja2 >= 2.9, not available as RPM :-(
yum -y install python-setuptools
easy_install pip
pip install 'jinja2 >= 2.9'

# eventhough swap is disabled, the assertion on it fails, set ignore_assert_errors=True
ansible-playbook -i inventory/local/hosts.ini -e ignore_assert_errors=True cluster.yml

popd

git clone https://github.com/gluster/gluster-kubernetes
pushd gluster-kubernetes/deploy

IPADDR=$(ip -4 -oneline addr show dev eth0 | awk -F '( +|/)' '{print $4}')
HOSTNAME=$(hostname)

cat << EOF > topology.json
{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                "${HOSTNAME}"
              ],
              "storage": [
                "${IPADDR}"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/vdb",
            "/dev/vdc",
            "/dev/vdd"
          ]
        }
      ]
    }
  ]
}
EOF

# if dm-thin-pool is not loaded yet, containers will fail to create LVs for the bricks
modprobe dm-thin-pool

./gk-deploy --yes --verbose --single-node --no-object --deploy-gluster --cli=kubectl topology.json

