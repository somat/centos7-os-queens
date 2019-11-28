#!/bin/bash

# === Define variable ===
# === START EDIT ===

STORAGE_1_DEVICE_1=vdb
STORAGE_1_DEVICE_2=vdc

STORAGE_2_DEVICE_1=vdb
STORAGE_2_DEVICE_2=vdc

CONTROLLER_MGMT_ADDR=10.100.0.5
STORAGE_MGMT_IP_ADDR=10.100.0.5

# === END EDIT ===

# Perform these steps on the controller node.

cd /etc/swift
swift-ring-builder account.builder create 10 3 1

swift-ring-builder account.builder add --region 1 --zone 1 --ip $CONTROLLER_MGMT_ADDR --port 6202 --device $STORAGE_1_DEVICE_1 --weight 100
swift-ring-builder account.builder add --region 1 --zone 1 --ip $CONTROLLER_MGMT_ADDR --port 6202 --device $STORAGE_1_DEVICE_2 --weight 100
swift-ring-builder account.builder add --region 1 --zone 2 --ip $STORAGE_MGMT_IP_ADDR --port 6202 --device $STORAGE_2_DEVICE_1 --weight 100
swift-ring-builder account.builder add --region 1 --zone 2 --ip $STORAGE_MGMT_IP_ADDR --port 6202 --device $STORAGE_2_DEVICE_2 --weight 100

swift-ring-builder account.builder
swift-ring-builder account.builder rebalance

swift-ring-builder container.builder create 10 3 1

swift-ring-builder container.builder add --region 1 --zone 1 --ip $CONTROLLER_MGMT_ADDR --port 6201 --device $STORAGE_1_DEVICE_1 --weight 100
swift-ring-builder container.builder add --region 1 --zone 1 --ip $CONTROLLER_MGMT_ADDR --port 6201 --device $STORAGE_1_DEVICE_2 --weight 100
swift-ring-builder container.builder add --region 1 --zone 2 --ip $STORAGE_MGMT_IP_ADDR --port 6201 --device $STORAGE_2_DEVICE_1 --weight 100
swift-ring-builder container.builder add --region 1 --zone 2 --ip $STORAGE_MGMT_IP_ADDR --port 6201 --device $STORAGE_2_DEVICE_2 --weight 100

swift-ring-builder container.builder
swift-ring-builder container.builder rebalance

swift-ring-builder object.builder create 10 3 1
swift-ring-builder object.builder add --region 1 --zone 1 --ip $CONTROLLER_MGMT_ADDR --port 6200 --device $STORAGE_1_DEVICE_1 --weight 100
swift-ring-builder object.builder add --region 1 --zone 1 --ip $CONTROLLER_MGMT_ADDR --port 6200 --device $STORAGE_1_DEVICE_2 --weight 100
swift-ring-builder object.builder add --region 1 --zone 2 --ip $STORAGE_MGMT_IP_ADDR --port 6200 --device $STORAGE_2_DEVICE_1 --weight 100
swift-ring-builder object.builder add --region 1 --zone 2 --ip $STORAGE_MGMT_IP_ADDR --port 6200 --device $STORAGE_2_DEVICE_2 --weight 100

swift-ring-builder object.builder
swift-ring-builder object.builder rebalance

echo "Copy the account.ring.gz, container.ring.gz, and object.ring.gz files to the /etc/swift directory on each storage node and any additional nodes running the proxy service."

echo "Finished ...."
