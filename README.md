# centos7-os-queens
Install OpenStack Queens on CentOS 7

## Install

1. Edit and run controller.sh on controller node
2. Edit and run compute.sh on compute node
3. Edit and run controller-cinder.sh on controller to install cinder service
4. Edit and run storage-cinder.sh to install cinder on storage node
5. Edit and run heat-controller.sh to install heat service on controller
6. To install swift, check swift/README.md

## Verify installation

```
# . admin-openrc
# openstack compute service list
# openstack catalog list
# openstack network agent list
```
