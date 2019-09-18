#!/bin/bash

STORAGE_DEVICE_1=vdb
STORAGE_DEVICE_2=vdc
STORAGE_MGMT_IP_ADDR=10.100.0.5

yum -y install xfsprogs rsync

mkfs.xfs /dev/$STORAGE_DEVICE_1
mkfs.xfs /dev/$STORAGE_DEVICE_2

mkdir -p /srv/node/$STORAGE_DEVICE_1
mkdir -p /srv/node/$STORAGE_DEVICE_2

echo "/dev/$STORAGE_DEVICE_1 /srv/node/$STORAGE_DEVICE_1 xfs noatime,nodiratime,nobarrier,logbufs=8 0 2" >> /etc/fstab
echo "/dev/$STORAGE_DEVICE_2 /srv/node/$STORAGE_DEVICE_2 xfs noatime,nodiratime,nobarrier,logbufs=8 0 2" >> /etc/fstab

mount /srv/node/$STORAGE_DEVICE_1
mount /srv/node/$STORAGE_DEVICE_2

cat >/etc/rsyncd.conf <<EOF
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = $STORAGE_MGMT_IP_ADDR

[account]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/account.lock

[container]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/container.lock

[object]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/object.lock
EOF

systemctl enable rsyncd.service
systemctl start rsyncd.service

yum -y install openstack-swift-account openstack-swift-container openstack-swift-object

cat >/etc/swift/account-server.conf <<EOF
[DEFAULT]
bind_ip = $STORAGE_MGMT_IP_ADDR
bind_port = 6202
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = true

[pipeline:main]
pipeline = healthcheck recon account-server

[app:account-server]
use = egg:swift#account

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift

[account-replicator]

[account-auditor]

[account-reaper]

[filter:xprofile]
use = egg:swift#xprofile
EOF

cat >/etc/swift/container-server.conf <<EOF
[DEFAULT]
bind_ip = $STORAGE_MGMT_IP_ADDR
bind_port = 6201
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = true

[pipeline:main]
pipeline = healthcheck recon container-server

[app:container-server]
use = egg:swift#container

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:recon]
use = egg:swift#recon
econ_cache_path = /var/cache/swift

[container-replicator]

[container-updater]

[container-auditor]

[container-sync]

[filter:xprofile]
use = egg:swift#xprofile
EOF

cat >/etc/swift/object-server.conf <<EOF
[DEFAULT]
bind_ip = $STORAGE_MGMT_IP_ADDR
bind_port = 6200
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = true

[pipeline:main]
pipeline = healthcheck recon object-server

[app:object-server]
use = egg:swift#object

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
recon_lock_path = /var/lock

[object-replicator]

[object-reconstructor]

[object-updater]

[object-auditor]

[filter:xprofile]
use = egg:swift#xprofile
EOF

chown -R swift:swift /srv/node
mkdir -p /var/cache/swift
chown -R root:swift /var/cache/swift
chmod -R 775 /var/cache/swift
