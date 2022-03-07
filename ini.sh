sudo su

sudo apt-get update
sudo apt-get install --no-install-recommends -y git

git clone https://opendev.org/openstack/openstack-helm-infra.git /opt/openstack-helm-infra
git clone https://opendev.org/openstack/openstack-helm.git /opt/openstack-helm

