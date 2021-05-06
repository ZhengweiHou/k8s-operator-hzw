# !/bin/bash
CLUSTER_NAME='myk8s'
CONTEXT_NAME='myk8s-context'
M_SERVER='https://172.10.10.100:6443'
CONFIGFILE='kubelet.kubeconfig'
USER='k8s-node-client'
CERTS_DIR='/data/NFS_SHARE/certs'
certificate_authority="${CERTS_DIR}/ca.pem"
client_certificat="${CERTS_DIR}/k8s-node-client.pem"
client_key="${CERTS_DIR}/k8s-node-client-key.pem"
embed_certs=true

mv ${CONFIGFILE} /tmp/

kubectl config set-cluster ${CLUSTER_NAME} \
   --certificate-authority=${certificate_authority} \
   --embed-certs=${embed_certs} \
   --server=${M_SERVER} \
   --kubeconfig=${CONFIGFILE}

kubectl config set-credentials ${USER} \
  --client-certificate=${client_certificat} \
  --client-key=${client_key} \
  --embed-certs=${embed_certs} \
  --kubeconfig=${CONFIGFILE}

kubectl config set-context ${CONTEXT_NAME} \
   --cluster=${CLUSTER_NAME} \
   --user=${USER} \
   --kubeconfig=${CONFIGFILE}

kubectl config use-context ${CONTEXT_NAME} --kubeconfig=${CONFIGFILE}
