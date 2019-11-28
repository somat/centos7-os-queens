#!/bin/bash

echo "=== Install and Setup OpenStack Queens CentOS 7 on Controller Node ==="

yum -y update

# == Define variable ==
# === START EDIT ===
CONTROLLER_PROVIDER_INTERFACE=eth1
CONTROLLER_MGMT_ADDR=10.100.0.5
COMPUTE1_MGMT_ADDR=10.100.0.6

RABBIT_PASS=rahasia
MYSQL_PASS=rahasia

KEYSTONE_DBPASS=rahasia
KEYSTONE_ADMIN_PASS=rahasia
KEYSTONE_USER_PASS=rahasia

GLANCE_DBPASS=rahasia
GLANCE_USER_PASS=rahasia

NOVA_DBPASS=rahasia
PLACEMENT_DBPASS=rahasia
NOVA_USER_PASS=rahasia
NOVA_PLACEMENT_PASS=rahasia

NEUTRON_DBPASS=rahasia
NEUTRON_USER_PASS=rahasia
METADATA_USER_PASS=rahasia

# === END EDIT ===

echo "Controller IP ADDR = $CONTROLLER_MGMT_ADDR"
echo "Compute 1 IP ADDR = $COMPUTE1_MGMT_ADDR"

# === Disabling Firewalld ===

systemctl stop firewalld
systemctl disable firewalld

# === crete hosts file
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Creating hosts file ..."

cat >>/etc/hosts <<EOF
$CONTROLLER_MGMT_ADDR    controller
$COMPUTE1_MGMT_ADDR    compute1
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

# === Install MySQL
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing MySQL Package ..."
yum -y install mariadb mariadb-server python2-PyMySQL

cat >/etc/my.cnf.d/openstack.cnf <<EOF
[mysqld]
bind-address = $CONTROLLER_MGMT_ADDR

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

systemctl enable mariadb.service
systemctl start mariadb.service

mysql_secure_installation <<EOF

y
$MYSQL_PASS
$MYSQL_PASS
y
y
y
y
EOF

# === Install Message Queue
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing Messaging Queue ..."
yum -y install rabbitmq-server
systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service

rabbitmqctl add_user openstack $RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# === Memcached
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing Memcached ..."
yum -y install memcached python-memcached
cat >/etc/sysconfig/memcached <<EOF
PORT="11211"
USER="memcached"
MAXCONN="1024"
CACHESIZE="64"
OPTIONS="-l 127.0.0.1,::1,controller"
EOF

systemctl enable memcached.service
systemctl start memcached.service

# === ETCD
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing ETCD ..."
yum -y install etcd

cat >/etc/etcd/etcd.conf <<EOF
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://$CONTROLLER_MGMT_ADDR:2380"
ETCD_LISTEN_CLIENT_URLS="http://$CONTROLLER_MGMT_ADDR:2379"
ETCD_NAME="controller"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$CONTROLLER_MGMT_ADDR:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://$CONTROLLER_MGMT_ADDR:2379"
ETCD_INITIAL_CLUSTER="controller=http://$CONTROLLER_MGMT_ADDR:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

systemctl enable etcd
systemctl start etcd

# === INSTALL KEYSTONE
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing KEYSTONE ..."

mysql -uroot -p$MYSQL_PASS <<KEYSTONE_QUERY
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';
KEYSTONE_QUERY

yum -y install openstack-keystone httpd mod_wsgi
cat >/etc/keystone/keystone.conf <<EOF
[DEFAULT]
[application_credential]
[assignment]
[auth]
[cache]
[catalog]
[cors]
[credential]

[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@controller/keystone

[domain_config]
[endpoint_filter]
[endpoint_policy]
[eventlet_server]
[federation]
[fernet_tokens]
[healthcheck]
[identity]
[identity_mapping]
[ldap]
[matchmaker_redis]
[memcache]
[oauth1]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[policy]
[profiler]
[resource]
[revoke]
[role]
[saml]
[security_compliance]
[shadow_users]
[signing]

[token]
provider = fernet

[tokenless_auth]
[trust]
[unified_limit]
[wsgi]
EOF

su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password $KEYSTONE_ADMIN_PASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne

cat >/etc/httpd/conf/httpd.conf <<EOF
ServerRoot "/etc/httpd"
Listen 80
Include conf.modules.d/*.conf
User apache
Group apache
ServerAdmin root@localhost
ServerName controller
<Directory />
    AllowOverride none
    Require all denied
</Directory>

DocumentRoot "/var/www/html"

<Directory "/var/www">
    AllowOverride None
    Require all granted
</Directory>

<Directory "/var/www/html">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<IfModule dir_module>
    DirectoryIndex index.html
</IfModule>

<Files ".ht*">
    Require all denied
</Files>

ErrorLog "logs/error_log"

LogLevel warn

<IfModule log_config_module>
    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common

    <IfModule logio_module>
        LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %I %O" combinedio
    </IfModule>
        CustomLog "logs/access_log" combined
</IfModule>

<IfModule alias_module>
    ScriptAlias /cgi-bin/ "/var/www/cgi-bin/"
</IfModule>

<Directory "/var/www/cgi-bin">
    AllowOverride None
    Options None
    Require all granted
</Directory>

<IfModule mime_module>
    TypesConfig /etc/mime.types
    AddType application/x-compress .Z
    AddType application/x-gzip .gz .tgz
    AddType text/html .shtml
    AddOutputFilter INCLUDES .shtml
</IfModule>

AddDefaultCharset UTF-8

<IfModule mime_magic_module>
    MIMEMagicFile conf/magic
</IfModule>

EnableSendfile on

IncludeOptional conf.d/*.conf
EOF

ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable httpd.service
systemctl start httpd.service

export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3

openstack domain create --description "An Example Domain" example
openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" myproject
openstack user create --domain default --password $KEYSTONE_USER_PASS myuser
openstack role create myrole
openstack role add --project myproject --user myuser myrole

cat >~/admin-openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

cat >~/user-openrc <<EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=myproject
export OS_USERNAME=myuser
export OS_PASSWORD=$KEYSTONE_USER_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

# === Install Glance ===
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing Glance Packages ..."

mysql -uroot -p$MYSQL_PASS <<GLANCE_QUERY
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';
GLANCE_QUERY

source ~/admin-openrc

openstack user create --domain default --password $GLANCE_USER_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292

yum -y install openstack-glance

cat >/etc/glance/glance-api.conf <<EOF
[DEFAULT]
[cors]

[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@controller/glance

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/

[image_format]

[keystone_authtoken]
www_authenticate_uri  = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $GLANCE_USER_PASS

[matchmaker_redis]
[oslo_concurrency]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]

[paste_deploy]
flavor = keystone

[profiler]
[store_type_location_strategy]
[task]
[taskflow_executor]
EOF

cat >/etc/glance/glance-registry.conf <<EOF
[DEFAULT]

[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@controller/glance

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $GLANCE_USER_PASS

[matchmaker_redis]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_policy]

[paste_deploy]
flavor = keystone

[profiler]
EOF

su -s /bin/sh -c "glance-manage db_sync" glance

systemctl enable openstack-glance-api.service openstack-glance-registry.service
systemctl start openstack-glance-api.service openstack-glance-registry.service

# ==== Install Compute on Controller ====
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing compute (Nova) on controller ..."

mysql -uroot -p$MYSQL_PASS <<NOVA_QUERY
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;

GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';

GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';

GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
NOVA_QUERY

openstack user create --domain default --password $NOVA_USER_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1

openstack user create --domain default --password $NOVA_PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778

yum -y install openstack-nova-api openstack-nova-conductor \
  openstack-nova-console openstack-nova-novncproxy \
  openstack-nova-scheduler openstack-nova-placement-api

cat >/etc/nova/nova.conf <<EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:$RABBIT_PASS@controller
my_ip = $CONTROLLER_MGMT_ADDR
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api]
auth_strategy = keystone

[api_database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@controller/nova_api

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
connection = mysql+pymysql://nova:$NOVA_DBPASS@controller/nova

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
service_metadata_proxy = true
metadata_proxy_shared_secret = $METADATA_USER_PASS

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
connection = mysql+pymysql://placement:$PLACEMENT_DBPASS@controller/placement

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
server_listen = \$my_ip
server_proxyclient_address = \$my_ip

[workarounds]
[wsgi]
[xenserver]
[xvp]
[zvm]
EOF

cat >>/etc/httpd/conf.d/00-nova-placement-api.conf <<EOF

<Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
</Directory>
EOF

systemctl restart httpd

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova

su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova

systemctl enable openstack-nova-api.service \
  openstack-nova-consoleauth openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service

systemctl start openstack-nova-api.service \
  openstack-nova-consoleauth openstack-nova-scheduler.service \
  openstack-nova-conductor.service openstack-nova-novncproxy.service

# ==== Install Neutron Package ====
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing neutron packages ...."

mysql -uroot -p$MYSQL_PASS <<NEUTRON_QUERY
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';
NEUTRON_QUERY

openstack user create --domain default --password $NEUTRON_USER_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin http://controller:9696

# == Use Option 2 (self service) networking
yum -y install openstack-neutron openstack-neutron-ml2 \
  openstack-neutron-openvswitch ebtables

cat >/etc/neutron/neutron.conf <<EOF
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:$RABBIT_PASS@controller
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[agent]
[cors]

[database]
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@controller/neutron

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
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_USER_PASS

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

cat >/etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
[DEFAULT]
[l2pop]

[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch,l2population
extension_drivers = port_security,qos
path_mtu=0

[ml2_type_flat]
flat_networks =*

[ml2_type_geneve]
[ml2_type_gre]
[ml2_type_vlan]

[ml2_type_vxlan]
vni_ranges=10:1000
vxlan_group=224.0.0.1

[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
enable_security_group=True
enable_ipset = true
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
local_ip=$CONTROLLER_MGMT_ADDR
bridge_mappings=extnet:br-ex
[securitygroup]
firewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
[xenapi]
EOF

cat >/etc/neutron/l3_agent.ini <<EOF
[DEFAULT]
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
agent_mode=legacy
[agent]
[ovs]
EOF

cat >/etc/neutron/dhcp_agent.ini <<EOF
[DEFAULT]
interface_driver=neutron.agent.linux.interface.OVSInterfaceDriver
resync_interval=30
enable_isolated_metadata=False
enable_metadata_network=False
debug=False
state_path=/var/lib/neutron
root_helper=sudo neutron-rootwrap /etc/neutron/rootwrap.conf
[agent]
[ovs]
EOF

cat >/etc/neutron/metadata_agent.ini <<EOF
[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = $METADATA_USER_PASS
metadata_workers = 4
[agent]
[cache]
EOF

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

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

cat >/etc/sysconfig/network-scripts/ifcfg-$CONTROLLER_PROVIDER_INTERFACE <<EOF
DEVICE=$CONTROLLER_PROVIDER_INTERFACE
NAME=$CONTROLLER_PROVIDER_INTERFACE
DEVICETYPE=ovs
TYPE=OVSPort
OVS_BRIDGE=br-ex
ONBOOT=yes
BOOTPROTO=none
EOF

systemctl restart network
systemctl restart openstack-nova-api.service
systemctl enable neutron-server.service \
  neutron-openvswitch-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service

systemctl start neutron-server.service \
  neutron-openvswitch-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service

systemctl enable neutron-l3-agent.service
systemctl start neutron-l3-agent.service

printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Installing Horizon packages ...."

yum -y install openstack-dashboard

cat >/etc/openstack-dashboard/local_settings <<EOF
# -*- coding: utf-8 -*-

import os
from django.utils.translation import ugettext_lazy as _
from openstack_dashboard.settings import HORIZON_CONFIG

DEBUG = False
WEBROOT = '/dashboard/'
ALLOWED_HOSTS = ['controller', 'localhost']
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'Default'
LOCAL_PATH = '/tmp'
SECRET_KEY='3c1ea836bf8765cfb264'
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
        'LOCATION': 'controller:11211',
    },
}
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'
OPENSTACK_HOST = "controller"
OPENSTACK_KEYSTONE_URL = "http://%s:5000/v3" % OPENSTACK_HOST
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "myrole"
OPENSTACK_KEYSTONE_BACKEND = {
    'name': 'native',
    'can_edit_user': True,
    'can_edit_group': True,
    'can_edit_project': True,
    'can_edit_domain': True,
    'can_edit_role': True,
}
OPENSTACK_HYPERVISOR_FEATURES = {
    'can_set_mount_point': False,
    'can_set_password': False,
    'requires_keypair': False,
    'enable_quotas': True
}
OPENSTACK_CINDER_FEATURES = {
    'enable_backup': False,
}
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': True,
    'enable_quotas': True,
    'enable_ipv6': True,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_fip_topology_check': True,
    'supported_vnic_types': ['*'],
    'physical_networks': [],
}
OPENSTACK_HEAT_STACK = {
    'enable_user_pass': True,
}
IMAGE_CUSTOM_PROPERTY_TITLES = {
    "architecture": _("Architecture"),
    "kernel_id": _("Kernel ID"),
    "ramdisk_id": _("Ramdisk ID"),
    "image_state": _("Euca2ools state"),
    "project_id": _("Project ID"),
    "image_type": _("Image Type"),
}
IMAGE_RESERVED_CUSTOM_PROPERTIES = []
API_RESULT_LIMIT = 1000
API_RESULT_PAGE_SIZE = 20
SWIFT_FILE_TRANSFER_CHUNK_SIZE = 512 * 1024
INSTANCE_LOG_LENGTH = 35
DROPDOWN_MAX_ITEMS = 30
TIME_ZONE = "UTC"
POLICY_FILES_PATH = '/etc/openstack-dashboard'
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'console': {
            'format': '%(levelname)s %(name)s %(message)s'
        },
        'operation': {
            'format': '%(message)s'
        },
    },
    'handlers': {
        'null': {
            'level': 'DEBUG',
            'class': 'logging.NullHandler',
        },
        'console': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'console',
        },
        'operation': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'operation',
        },
    },
    'loggers': {
        'horizon': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'horizon.operation_log': {
            'handlers': ['operation'],
            'level': 'INFO',
            'propagate': False,
        },
        'openstack_dashboard': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'novaclient': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'cinderclient': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'keystoneauth': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'keystoneclient': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'glanceclient': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'neutronclient': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'swiftclient': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'oslo_policy': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'openstack_auth': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'django': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': False,
        },
        'django.db.backends': {
            'handlers': ['null'],
            'propagate': False,
        },
        'requests': {
            'handlers': ['null'],
            'propagate': False,
        },
        'urllib3': {
            'handlers': ['null'],
            'propagate': False,
        },
        'chardet.charsetprober': {
            'handlers': ['null'],
            'propagate': False,
        },
        'iso8601': {
            'handlers': ['null'],
            'propagate': False,
        },
        'scss': {
            'handlers': ['null'],
            'propagate': False,
        },
    },
}
SECURITY_GROUP_RULES = {
    'all_tcp': {
        'name': _('All TCP'),
        'ip_protocol': 'tcp',
        'from_port': '1',
        'to_port': '65535',
    },
    'all_udp': {
        'name': _('All UDP'),
        'ip_protocol': 'udp',
        'from_port': '1',
        'to_port': '65535',
    },
    'all_icmp': {
        'name': _('All ICMP'),
        'ip_protocol': 'icmp',
        'from_port': '-1',
        'to_port': '-1',
    },
    'ssh': {
        'name': 'SSH',
        'ip_protocol': 'tcp',
        'from_port': '22',
        'to_port': '22',
    },
    'smtp': {
        'name': 'SMTP',
        'ip_protocol': 'tcp',
        'from_port': '25',
        'to_port': '25',
    },
    'dns': {
        'name': 'DNS',
        'ip_protocol': 'tcp',
        'from_port': '53',
        'to_port': '53',
    },
    'http': {
        'name': 'HTTP',
        'ip_protocol': 'tcp',
        'from_port': '80',
        'to_port': '80',
    },
    'pop3': {
        'name': 'POP3',
        'ip_protocol': 'tcp',
        'from_port': '110',
        'to_port': '110',
    },
    'imap': {
        'name': 'IMAP',
        'ip_protocol': 'tcp',
        'from_port': '143',
        'to_port': '143',
    },
    'ldap': {
        'name': 'LDAP',
        'ip_protocol': 'tcp',
        'from_port': '389',
        'to_port': '389',
    },
    'https': {
        'name': 'HTTPS',
        'ip_protocol': 'tcp',
        'from_port': '443',
        'to_port': '443',
    },
    'smtps': {
        'name': 'SMTPS',
        'ip_protocol': 'tcp',
        'from_port': '465',
        'to_port': '465',
    },
    'imaps': {
        'name': 'IMAPS',
        'ip_protocol': 'tcp',
        'from_port': '993',
        'to_port': '993',
    },
    'pop3s': {
        'name': 'POP3S',
        'ip_protocol': 'tcp',
        'from_port': '995',
        'to_port': '995',
    },
    'ms_sql': {
        'name': 'MS SQL',
        'ip_protocol': 'tcp',
        'from_port': '1433',
        'to_port': '1433',
    },
    'mysql': {
        'name': 'MYSQL',
        'ip_protocol': 'tcp',
        'from_port': '3306',
        'to_port': '3306',
    },
    'rdp': {
        'name': 'RDP',
        'ip_protocol': 'tcp',
        'from_port': '3389',
        'to_port': '3389',
    },
}
REST_API_REQUIRED_SETTINGS = ['OPENSTACK_HYPERVISOR_FEATURES',
                              'LAUNCH_INSTANCE_DEFAULTS',
                              'OPENSTACK_IMAGE_FORMATS',
                              'OPENSTACK_KEYSTONE_BACKEND',
                              'OPENSTACK_KEYSTONE_DEFAULT_DOMAIN',
                              'CREATE_IMAGE_DEFAULTS',
                              'ENFORCE_PASSWORD_CHECK']
ALLOWED_PRIVATE_SUBNET_CIDR = {'ipv4': [], 'ipv6': []}
EOF

sed -i '4 i WSGIApplicationGroup %{GLOBAL}' /etc/httpd/conf.d/openstack-dashboard.conf
systemctl restart httpd.service memcached.service

printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
echo "Finished ..."
