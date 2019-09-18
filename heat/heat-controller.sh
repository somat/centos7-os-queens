MYSQL_PASS=rahasia
HEAT_DBPASS=rahasia
HEAT_USER_PASS=rahasia
HEAT_DOMAIN_USER_PASS=rahasia
RABBIT_PASS=rahasia
TRUSTEE_PASS=rahasia

mysql -uroot -p$MYSQL_PASS <<HEAT_QUERY
CREATE DATABASE heat;
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$HEAT_DBPASS';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$HEAT_DBPASS';
FLUSH PRIVILEGES;
HEAT_QUERY

. admin-openrc

openstack user create --domain default --password $HEAT_USER_PASS heat
openstack role add --project service --user heat admin
openstack service create --name heat --description "Orchestration" orchestration
openstack service create --name heat-cfn --description "Orchestration"  cloudformation
openstack endpoint create --region RegionOne orchestration public http://controller:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration internal http://controller:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration admin http://controller:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne cloudformation public http://controller:8000/v1
openstack endpoint create --region RegionOne cloudformation internal http://controller:8000/v1
openstack endpoint create --region RegionOne cloudformation admin http://controller:8000/v1
openstack domain create --description "Stack projects and users" heat
openstack user create --domain heat --password $HEAT_DOMAIN_USER_PASS heat_domain_admin
openstack role add --domain heat --user-domain heat --user heat_domain_admin admin
openstack role create heat_stack_owner
openstack role add --project demo --user demo heat_stack_owner
openstack role create heat_stack_user

yum install -y openstack-heat-api openstack-heat-api-cfn openstack-heat-engine openstack-heat-ui

cat >/etc/heat/heat.conf <<EOF
[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASS@controller
heat_metadata_server_url = http://controller:8000
heat_waitcondition_server_url = http://controller:8000/v1/waitcondition

stack_domain_admin = heat_domain_admin
stack_domain_admin_password = $HEAT_DOMAIN_USER_PASS
stack_user_domain_name = heat

[auth_password]
[clients]
[clients_aodh]
[clients_barbican]
[clients_ceilometer]
[clients_cinder]
[clients_designate]
[clients_glance]
[clients_heat]

[clients_keystone]
auth_uri = http://controller:5000

[clients_magnum]
[clients_manila]
[clients_mistral]
[clients_monasca]
[clients_neutron]
[clients_nova]
[clients_octavia]
[clients_sahara]
[clients_senlin]
[clients_swift]
[clients_trove]
[clients_zaqar]
[cors]

[database]
connection = mysql+pymysql://heat:$HEAT_DBPASS@controller/heat

[ec2authtoken]
[eventlet_opts]
[healthcheck]
[heat_api]
[heat_api_cfn]
[heat_api_cloudwatch]

[keystone_authtoken]
auth_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = heat
password = $HEAT_USER_PASS

[matchmaker_redis]
[noauth]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_messaging_zmq]
[oslo_middleware]
[oslo_policy]
[paste_deploy]
[profiler]
[revision]
[ssl]

[trustee]
auth_type = password
auth_url = http://controller:35357
username = heat
password = $TRUSTEE_PASS
user_domain_name = default

[volumes]
EOF

su -s /bin/sh -c "heat-manage db_sync" heat

systemctl enable openstack-heat-api.service openstack-heat-api-cfn.service openstack-heat-engine.service
systemctl start openstack-heat-api.service openstack-heat-api-cfn.service openstack-heat-engine.service
