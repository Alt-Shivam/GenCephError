# Get sudo working
sudo -l 

sudo apt-get update
sudo apt-get install --no-install-recommends -y git

git clone https://opendev.org/openstack/openstack-helm-infra.git /opt/openstack-helm-infra
git clone https://opendev.org/openstack/openstack-helm.git /opt/openstack-helm


git clone https://github.com/Alt-Shivam/UbuntuMachineSetup.git

cd UbuntuMachineSetup/

sudo cp Start.sh ../

cd ..

chmod 777 Start.sh

./Start.sh

cd /opt/openstack-helm

tee conf.yaml << EOF
# three node (two workers) cluster config
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF


kind create cluster --config conf.yaml

sudo -H -E pip3 install --upgrade pip
sudo -H -E pip3 install \
  -c${UPPER_CONSTRAINTS_FILE:=https://releases.openstack.org/constraints/upper/${OPENSTACK_RELEASE:-stein}} \
  cmd2 python-openstackclient python-heatclient --ignore-installed

export HELM_CHART_ROOT_PATH="${HELM_CHART_ROOT_PATH:="${OSH_INFRA_PATH:="../openstack-helm-infra"}"}"

sudo -H mkdir -p /etc/openstack
sudo -H chown -R $(id -un): /etc/openstack
FEATURE_GATE="tls"; if [[ ${FEATURE_GATES//,/ } =~ (^|[[:space:]])${FEATURE_GATE}($|[[:space:]]) ]]; then
  tee /etc/openstack/clouds.yaml << EOF
  clouds:
    openstack_helm:
      region_name: RegionOne
      identity_api_version: 3
      cacert: /etc/openstack-helm/certs/ca/ca.pem
      auth:
        username: 'admin'
        password: 'password'
        project_name: 'admin'
        project_domain_name: 'default'
        user_domain_name: 'default'
        auth_url: 'https://keystone.openstack.svc.cluster.local/v3'
EOF
else
  tee /etc/openstack/clouds.yaml << EOF
  clouds:
    openstack_helm:
      region_name: RegionOne
      identity_api_version: 3
      auth:
        username: 'admin'
        password: 'password'
        project_name: 'admin'
        project_domain_name: 'default'
        user_domain_name: 'default'
        auth_url: 'http://keystone.openstack.svc.cluster.local/v3'
EOF
fi

#NOTE: Build helm-toolkit, most charts depend on helm-toolkit
make -C ${HELM_CHART_ROOT_PATH} helm-toolkit


export OSH_DEPLOY_MULTINODE=True


export HELM_CHART_ROOT_PATH="${HELM_CHART_ROOT_PATH:="${OSH_INFRA_PATH:="../openstack-helm-infra"}"}"
: ${OSH_EXTRA_HELM_ARGS_INGRESS:="$(./tools/deployment/common/get-values-overrides.sh ingress)"}

#NOTE: Lint and package chart
make -C ${HELM_CHART_ROOT_PATH} ingress

#NOTE: Deploy command
: ${OSH_EXTRA_HELM_ARGS:=""}
tee /tmp/ingress-kube-system.yaml << EOF
deployment:
  mode: cluster
  type: DaemonSet
network:
  host_namespace: true
EOF

touch /tmp/ingress-component.yaml

if [ -n "${OSH_DEPLOY_MULTINODE}" ]; then
  tee --append /tmp/ingress-kube-system.yaml << EOF
pod:
  replicas:
    error_page: 4
EOF

  tee /tmp/ingress-component.yaml << EOF
pod:
  replicas:
    ingress: 4
    error_page: 4
EOF
fi



kubectl label nodes kind-control-plane kind-worker kind-worker2 kind-worker3 openstack-control-plane=enabled


helm upgrade --install ingress-kube-system ${HELM_CHART_ROOT_PATH}/ingress \
  --namespace=kube-system \
  --values=/tmp/ingress-kube-system.yaml \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS_KUBE_SYSTEM}

#NOTE: Wait for deploy
./tools/deployment/common/wait-for-pods.sh kube-system

kubectl create ns openstack

kubectl create ns ceph

#NOTE: Deploy namespace ingress
helm upgrade --install ingress-openstack ${HELM_CHART_ROOT_PATH}/ingress \
  --namespace=openstack \
  --values=/tmp/ingress-component.yaml \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS_OPENSTACK}

#NOTE: Wait for deploy
./tools/deployment/common/wait-for-pods.sh openstack

helm upgrade --install ingress-ceph ${HELM_CHART_ROOT_PATH}/ingress \
  --namespace=ceph \
  --values=/tmp/ingress-component.yaml \
  ${OSH_EXTRA_HELM_ARGS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS} \
  ${OSH_EXTRA_HELM_ARGS_INGRESS_CEPH}

