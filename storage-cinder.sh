#!/bin/bash

# == Define variable
LVM_PHYSICAL_VOLUME=/dev/vdb

RABBIT_PASS=rahasia
CINDER_DBPASS=rahasia
CINDER_USER_PASS=rahasia

STORAGE_MGMT_ADDR=10.100.0.5

yum -y install lvm2 device-mapper-persistent-data

systemctl enable lvm2-lvmetad.service
systemctl start lvm2-lvmetad.service

pvcreate LVM_PHYSICAL_VOLUME
vgcreate cinder-volumes LVM_PHYSICAL_VOLUME

yum -y install openstack-cinder targetcli python-keystone

# Update configuration
cat >/etc/cinder/cinder.conf <<EOF
[DEFAULT]
auth_strategy = keystone
transport_url = rabbit://openstack:$RABBIT_PASS@controller
my_ip = $STORAGE_MGMT_ADDR
enabled_backends = lvm
glance_api_servers = http://controller:9292

[backend]
[backend_defaults]
[barbican]
[brcd_fabric_example]
[cisco_fabric_example]
[coordination]
[cors]

[database]
connection = mysql+pymysql://cinder:$CINDER_DBPASS@controller/cinder

[fc-zone-manager]
[healthcheck]
[key_manager]

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = cinder
password = $CINDER_USER_PASS

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
iscsi_protocol = iscsi
iscsi_helper = lioadm

[matchmaker_redis]
[nova]

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
[oslo_versionedobjects]
[profiler]
[service_user]
[ssl]
[vault]
EOF

# Setup services
systemctl enable openstack-cinder-volume.service target.service
systemctl start openstack-cinder-volume.service target.service

echo "
Please update your /etc/lvm/lvm.conf 

devices {
...
filter = [ \"a/sdb/\", \"r/.*/\"]

"

echo "Finished ...."
