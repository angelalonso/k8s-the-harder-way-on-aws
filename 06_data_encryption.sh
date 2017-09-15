#!/usr/bin/env bash

#VARS
FOLDR="/home/aaf/Software/Dev/k8s-the-harder-way-on-aws/aux"
CFG="${FOLDR}/config.cfg"

. ${CFG}

encryption_config() {

echo "CONFIGURING ENCRYPTION!"

# Generate Encryption key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > ${CA_FOLDR}/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

for i in $(seq -w $NR_MASTERS); do
  scp -i ${SSHKEY} ${CA_FOLDR}/encryption-config.yaml ubuntu@${MASTER_IP_PUB[$i]}:~/
done
}

testing() {
  echo
}

encryption_config
#testing
