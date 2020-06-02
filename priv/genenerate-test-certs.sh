#!/usr/bin/env bash
mkdir -p configs/tls
mkdir -p configs/tls_expired_client_certs

cd configs

# CA
openssl genrsa -out tls/ca.key 4096
openssl req \
    -x509 -new -nodes -sha256 \
    -key tls/ca.key \
    -days 3650 \
    -subj '/O=Eredis Test/CN=Certificate Authority' \
    -out tls/ca.crt

# Redis server
openssl genrsa -out tls/redis.key 2048
openssl req \
    -new -sha256 \
    -key tls/redis.key \
    -subj '/O=Eredis Test/CN=Server' | \
    openssl x509 \
        -req -sha256 \
        -CA tls/ca.crt \
        -CAkey tls/ca.key \
        -CAserial tls/ca.txt \
        -CAcreateserial \
        -days 365 \
        -out tls/redis.crt

# eredis client
openssl genrsa -out tls/client.key 2048
openssl req \
    -new -sha256 \
    -key tls/client.key \
    -subj '/O=Eredis Test/CN=Client' | \
    openssl x509 \
        -req -sha256 \
        -CA tls/ca.crt \
        -CAkey tls/ca.key \
        -CAserial tls/ca.txt \
        -CAcreateserial \
        -days 365 \
        -out tls/client.crt

# Generate expired client cert
DIR=tls_expired_client_certs
cp tls/ca.crt ${DIR}/
openssl genrsa -out ${DIR}/client.key 2048

openssl req \
    -new -sha256 \
    -key ${DIR}/client.key \
    -subj '/O=Eredis Test/CN=Client' | \
    faketime '2020-01-01 10:00:00' \
        openssl x509 \
             -req -sha256 \
             -CA tls/ca.crt \
             -CAkey tls/ca.key \
             -CAserial tls/ca.txt \
             -CAcreateserial \
             -days 31 \
             -out ${DIR}/client.crt

# Make sure files are readable from the redis container
chmod 664 tls/*
chmod 664 tls_expired_client_certs/*
