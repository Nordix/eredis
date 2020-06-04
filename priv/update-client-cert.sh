#!/usr/bin/env bash
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/configs"

DIRNAME=${1:-tls_soon_expired_client_certs}

# Regenerate soon expired client cert
DIR=${BASEDIR}/${DIRNAME}/

mkdir -p ${DIR}
openssl genrsa -out ${DIR}/client.key 2048

cp ${BASEDIR}/tls/ca.crt ${DIR}/

# -60*24 + 1 minute ago, i.e. expires in 1 minute
openssl req \
    -new -sha256 \
    -key ${DIR}/client.key \
    -subj '/O=Eredis Test/CN=Client' | \
    faketime -f '-1439m' \
        openssl x509 \
             -req -sha256 \
             -CA       ${BASEDIR}/tls/ca.crt \
             -CAkey    ${BASEDIR}/tls/ca.key \
             -CAserial ${BASEDIR}/tls/ca.txt \
             -CAcreateserial \
             -days 1 \
             -out ${DIR}/client.crt

chmod 664 ${DIR}/*

