SWIFT_USER_PASS=rahasia

. admin-openrc

openstack user create --domain default --password $SWIFT_USER_PASS swift
openstack role add --project service --user swift admin
openstack service create --name swift --description "OpenStack Object Storage" object-store
openstack endpoint create --region RegionOne object-store public http://controller:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store internal http://controller:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store admin http://controller:8080/v1

yum -y install openstack-swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware memcached

cat >/etc/swift/proxy-server.conf <<EOF
[DEFAULT]
bind_port = 8080
swift_dir = /etc/swift
user = swift

[pipeline:main]
pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server

[app:proxy-server]
use = egg:swift#proxy
account_autocreate = true

[filter:authtoken]
paste.filter_factory = keystonemiddleware.auth_token:filter_factory
www_authenticate_uri = http://controller:5000
auth_url = http://controller:35357
memcached_servers = controller:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = swift
password = $SWIFT_USER_PASS
delay_auth_decision = True

[filter:keystoneauth]
use = egg:swift#keystoneauth
operator_roles = admin,user

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:cache]
use = egg:swift#memcache
memcache_servers = controller:11211

[filter:ratelimit]
use = egg:swift#ratelimit

[filter:domain_remap]
use = egg:swift#domain_remap

[filter:catch_errors]
use = egg:swift#catch_errors

[filter:cname_lookup]
use = egg:swift#cname_lookup

[filter:staticweb]
use = egg:swift#staticweb

[filter:tempurl]
use = egg:swift#tempurl

[filter:formpost]
use = egg:swift#formpost

[filter:name_check]
use = egg:swift#name_check

[filter:list-endpoints]
use = egg:swift#list_endpoints

[filter:proxy-logging]
use = egg:swift#proxy_logging

[filter:bulk]
use = egg:swift#bulk

[filter:slo]
use = egg:swift#slo

[filter:dlo]
use = egg:swift#dlo

[filter:container-quotas]
use = egg:swift#container_quotas

[filter:account-quotas]
use = egg:swift#account_quotas

[filter:gatekeeper]
use = egg:swift#gatekeeper

[filter:container_sync]
use = egg:swift#container_sync

[filter:xprofile]
use = egg:swift#xprofile

[filter:versioned_writes]
use = egg:swift#versioned_writes

[filter:copy]
use = egg:swift#copy

[filter:keymaster]
use = egg:swift#keymaster
encryption_root_secret = changeme

[filter:kms_keymaster]
use = egg:swift#kms_keymaster

[filter:encryption]
use = egg:swift#encryption

[filter:listing_formats]
use = egg:swift#listing_formats

[filter:symlink]
use = egg:swift#symlink
EOF

echo "Finished ....."
