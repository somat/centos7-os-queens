MYSQL_PASS=rahasia
CINDER_DBPASS=rahasia
CINDER_USER_PASS=rahasia
RABBIT_PASS=rahasia


mysql -uroot -p$MYSQL_PASS <<CINDER_QUERY
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';
FLUSH PRIVILEGES;
CINDER_QUERY

. admin-openrc

openstack user create --domain default --password $CINDER_USER_PASS cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne volumev2 public http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 internal http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 admin http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 public http://controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://controller:8776/v3/%\(project_id\)s

yum -y install openstack-cinder crudini

cat >/etc/cinder/cinder.conf <<EOF
[DEFAULT]
auth_strategy = keystone
transport_url = rabbit://openstack:$RABBIT_PASS@controller
my_ip = $CONTROLLER_MGMT_ADDR

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

su -s /bin/sh -c "cinder-manage db sync" cinder

crudini --set /etc/nova/nova.conf cinder os_region_name RegionOne

systemctl restart openstack-nova-api.service
systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
systemctl start openstack-cinder-api.service openstack-cinder-scheduler.service

openstack volume service list

echo "Finished ....."
