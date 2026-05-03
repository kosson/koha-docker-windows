#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$SCRIPT_DIR/opensearch_installer_vars.cfg"

if [ -f "$config_file" ]; then
    source "$config_file"
    # Root CA key creation
    openssl genrsa -out $OS_CERTS_PATH/root-ca-key.pem 2048
    openssl req -new -x509 -sha256 -key $OS_CERTS_PATH/root-ca-key.pem -subj "$CERT_DN/CN=$LOCAL_ROOT_CA" -out $OS_CERTS_PATH/root-ca.pem -days 730
    # TSL certificate for the administrator
    openssl genrsa -out $OS_CERTS_PATH/$ADMIN_CA-key-temp.pem 2048
    openssl pkcs8 -inform PEM -outform PEM -in $OS_CERTS_PATH/$ADMIN_CA-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out $OS_CERTS_PATH/$ADMIN_CA-key.pem
    openssl req -new -key $OS_CERTS_PATH/$ADMIN_CA-key.pem -subj "$CERT_DN/CN=$ADMIN_CA" -out $OS_CERTS_PATH/$ADMIN_CA.csr
    openssl x509 -req -in $OS_CERTS_PATH/$ADMIN_CA.csr -CA $OS_CERTS_PATH/root-ca.pem -CAkey $OS_CERTS_PATH/root-ca-key.pem -CAcreateserial -sha256 -out $OS_CERTS_PATH/$ADMIN_CA.pem -days 730
    # TLS certificate for the nodes
    for NODE_NAME in "os01" "os02" "os03" "os04" "os05" "client" "dashboards"
    do
        openssl genrsa -out $OS_CERTS_PATH/$NODE_NAME-key-temp.pem 2048
        openssl pkcs8 -inform PEM -outform PEM -in $OS_CERTS_PATH/$NODE_NAME-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out $OS_CERTS_PATH/$NODE_NAME-key.pem
        openssl req -new -key $OS_CERTS_PATH/$NODE_NAME-key.pem -subj $CERT_DN/CN=$NODE_NAME -out $OS_CERTS_PATH/$NODE_NAME.csr
        echo "subjectAltName=DNS:$NODE_NAME" > $OS_CERTS_PATH/$NODE_NAME.ext
        openssl x509 -req -in $OS_CERTS_PATH/$NODE_NAME.csr -CA $OS_CERTS_PATH/root-ca.pem -CAkey $OS_CERTS_PATH/root-ca-key.pem -CAcreateserial -sha256 -out $OS_CERTS_PATH/$NODE_NAME.pem -days 730 -extfile $OS_CERTS_PATH/$NODE_NAME.ext
        rm $OS_CERTS_PATH/$NODE_NAME-key-temp.pem $OS_CERTS_PATH/$NODE_NAME.csr $OS_CERTS_PATH/$NODE_NAME.ext
        chown -R 1000:1000 $OS_CERTS_PATH/$NODE_NAME-key.pem $OS_CERTS_PATH/$NODE_NAME.pem
    done
else
    echo "$config_file not found."    
fi

rm -f $OS_CERTS_PATH/$ADMIN_CA.csr $OS_CERTS_PATH/$ADMIN_CA-key-temp.pem
rm -f $OS_CERTS_PATH/root-ca.srl

# --- Compliance salt and SQL datasource master key ---------------------------------
# Both values must be identical on every node. They are generated once here and
# written into all os*/opensearch.yml files so the cluster is consistent.
#
# WARNING: Do NOT regenerate the SQL masterkey after the cluster has been used to
# store datasource credentials — re-running this script on an existing cluster will
# produce a new key and make any previously stored encrypted credentials unreadable.
# Run this script only when setting up a fresh cluster (after restart-to-clear-cluster.sh).

COMPLIANCE_SALT="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)"
SQL_MASTERKEY="$(openssl rand -hex 16)"
CONFIG_BASE="$SCRIPT_DIR/assets/opensearch/config"

for cfg in "$CONFIG_BASE"/os*/opensearch.yml; do
    if grep -q "^plugins.security.compliance.salt:" "$cfg"; then
        sed -i "s|^plugins.security.compliance.salt:.*|plugins.security.compliance.salt: \"$COMPLIANCE_SALT\"|" "$cfg"
    else
        echo "plugins.security.compliance.salt: \"$COMPLIANCE_SALT\"" >> "$cfg"
    fi
    if grep -q "^plugins.query.datasources.encryption.masterkey:" "$cfg"; then
        sed -i "s|^plugins.query.datasources.encryption.masterkey:.*|plugins.query.datasources.encryption.masterkey: \"$SQL_MASTERKEY\"|" "$cfg"
    else
        echo "plugins.query.datasources.encryption.masterkey: \"$SQL_MASTERKEY\"" >> "$cfg"
    fi
done
echo "Compliance salt and SQL master key written to all node configs."
echo "  compliance salt : $COMPLIANCE_SALT"
echo "  SQL master key  : $SQL_MASTERKEY"
echo "Store these values securely — they are required to restore the cluster."

# --- Secure file permissions -------------------------------------------------------
# Config files and private keys must not be world-readable. The Security plugin will
# log permission warnings at startup if these are not set correctly.
find "$SCRIPT_DIR/assets/ssl"                        -type f -name "*.pem" | xargs chmod 600
find "$SCRIPT_DIR/assets/opensearch/config"          -type d               | xargs chmod 700
find "$SCRIPT_DIR/assets/opensearch/config"          -type f               | xargs chmod 600
find "$SCRIPT_DIR/assets/opensearch/performance-analyzer" -type f          | xargs chmod 600 2>/dev/null || true
echo "File permissions set (certs: 600, config dirs: 700, config files: 600)."