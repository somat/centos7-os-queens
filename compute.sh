#!/bin/bash

echo "=== Install and Setup OpenStack Queens on Compute Node ==="

yum -y update

# == Define variable ==
CONTROLLER_MGMT_ADDR=10.100.0.5
COMPUTE1_MGMT_ADDR=10.100.0.6
COMPUTE1_PROVIDER_INTERFACE=eth1

RABBIT_PASS=rahasia

NOVA_USER_PASS=rahasia
NOVA_PLACEMENT_PASS=rahasia

NEUTRON_USER_PASS=rahasia

echo "Controller IP ADDR = $CONTROLLER_MGMT_ADDR"
echo "Compute 1 IP ADDR = $COMPUTE1_MGMT_ADDR"

# === Disabling Firewalld ===

systemctl stop firewalld
systemctl disable firewalld

# === crete hosts file
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Creating hosts file ..."

cat >>/etc/hosts <<EOF
$CONTROLLER_MGMT_ADDR   controller
$COMPUTE1_MGMT_ADDR     compute1
EOF

# === NTP
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing NTP Package  ..."
yum -y install chrony
systemctl enable chronyd.service
systemctl start chronyd.service

# === Install OpenStack Package
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing OpenStack Packages ..."
yum -y install centos-release-openstack-queens
yum -y upgrade
yum -y install python-openstackclient
yum -y install openstack-selinux

# === Install Nova packages
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing Nova Packages ..."

yum -y install openstack-nova-compute

cat >/etc/nova/nova.conf <<EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:$RABBIT_PASS@controller
my_ip = $COMPUTE1_MGMT_ADDR
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api]
auth_strategy = keystone

[api_database]
[barbican]
[cache]
[cells]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[database]
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]

[glance]
api_servers = http://controller:9292

[guestfs]
[healthcheck]
[hyperv]
[ironic]
[key_manager]
[keystone]

[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = $NOVA_USER_PASS

[libvirt]
virt_type=kvm
cpu_mode=host-passthrough

[matchmaker_redis]
[metrics]
[mks]

[neutron]
url = http://controller:9696
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_USER_PASS

[notifications]
[osapi_v21]

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[pci]

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = $NOVA_PLACEMENT_PASS

[placement_database]
[powervm]
[profiler]
[quota]
[rdp]
[remote_debug]
[scheduler]
[serial_console]
[service_user]
[spice]
[upgrade_levels]
[vault]
[vendordata_dynamic_auth]
[vmware]

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = \$my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html

[workarounds]
[wsgi]
[xenserver]
[xvp]
[zvm]
EOF

systemctl enable libvirtd.service openstack-nova-compute.service
systemctl start libvirtd.service openstack-nova-compute.service

# === Install Neutron Packages

printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing Neutron Packages ..."

yum -y install openstack-neutron-openvswitch ebtables ipset

cat >/etc/neutron/neutron.conf <<EOF
[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASS@controller
auth_strategy = keystone

[agent]
[cors]
[database]

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_USER_PASS

[matchmaker_redis]
[nova]

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp

[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[quotas]
[ssl]
EOF

cat >/etc/neutron/plugins/ml2/openvswitch_agent.ini <<EOF
[DEFAULT]

[agent]
tunnel_types=vxlan
vxlan_udp_port=4789
l2_population=False
drop_flows_on_start=False

[network_log]
[ovs]
integration_bridge=br-int
tunnel_bridge=br-tun
local_ip=$COMPUTE1_MGMT_ADDR
bridge_mappings=extnet:br-ex

[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

[xenapi]
EOF

cat >/etc/sysconfig/network-scripts/ifcfg-br-ex <<EOF
PROXY_METHOD=none
BROWSER_ONLY=no
DEFROUTE=yes
ONBOOT=yes
DEVICE=br-ex
NAME=br-ex
DEVICETYPE=ovs
OVSBOOTPROTO=none
TYPE=OVSBridge
OVS_EXTRA="set bridge br-ex fail_mode=standalone"
EOF

cat >/etc/sysconfig/network-scripts/$COMPUTE1_PROVIDER_INTERFACE <<EOF
DEVICE=$COMPUTE1_PROVIDER_INTERFACE
NAME=$COMPUTE1_PROVIDER_INTERFACE
DEVICETYPE=ovs
TYPE=OVSPort
OVS_BRIDGE=br-ex
ONBOOT=yes
BOOTPROTO=none
EOF

systemctl restart openstack-nova-compute.service
systemctl enable neutron-openvswitch-agent.service
systemctl start neutron-openvswitch-agent.service

printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Finished ..."
echo "Dont forget to discover compute on controller by running:"
echo "su -s /bin/sh -c 'nova-manage cell_v2 discover_hosts --verbose' nova"