#!/bin/bash

packstack --gen-answer-file /root/packstack_answers.txt

cat > /tmp/sed.script << EOF
s/\(CONFIG_KEYSTONE_ADMIN_PW=\).*/\1openstack/g
s/\(CONFIG_HEAT_INSTALL=\).*/\1y/g
s/\(CONFIG_NTP_SERVERS=\).*/\110.0.0.251/g

s/\(CONFIG_COMPUTE_HOSTS=\).*/\110.0.0.1,10.0.0.2,10.0.0.3/g

s/\(CONFIG_USE_EPEL=\).*/\1n/g
s/\(CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=\).*/\1physnet_ex:br-ex,physnet_mgmt:br-mgmt/g
s/\(CONFIG_NEUTRON_OVS_BRIDGE_IFACES=\).*/\1br-ex:enp2s1f1,br-mgmt:enp2s1f0/g
s/\(CONFIG_PROVISION_DEMO=\).*/\1n/g
EOF

sed -i -f /tmp/sed.script /root/packstack_answers.txt

packstack --answer-file /root/packstack_answers.txt

. /root/keystonerc_admin
neutron net-create ext_net --router:external=True
neutron subnet-create --name ext_subnet --disable-dhcp ext_net 192.168.33.0/24 \
   --gateway 192.168.33.254 --allocation-pool start=192.168.33.161,end=192.168.33.190

wget --no-check-certificate https://download.cirros-cloud.net/0.3.3/cirros-0.3.3-x86_64-disk.img

glance image-create --name cirros --is-public=True --disk-format=qcow2 \
   --container-format=bare --disk-format=qcow2 --file /root/cirros-0.3.3-x86_64-disk.img

keystone tenant-create --name demo
keystone user-create --name demo --pass demo
keystone user-role-add --user demo --role _member_ --tenant demo

cat > /root/keystonerc_demo << EOF
export OS_USERNAME=demo
export OS_TENANT_NAME=demo
export OS_PASSWORD=demo
export OS_AUTH_URL=http://10.0.0.1:5000/v2.0/
export PS1='[\u@\h \W(keystone_demo)]\$ '
EOF

. /root/keystonerc_demo

ssh-keygen -t rsa -b 4096 -N '' -f /root/id_rsa_demo
nova keypair-add --pub-key /root/id_rsa_demo.pub demo_key

neutron net-create stack_net_priv
neutron subnet-create --name stack_subnet_priv --dns-nameserver 8.8.8.8 stack_net_priv 10.0.8.0/24

neutron router-create extnet_stackrouter
neutron router-gateway-set extnet_stackrouter ext_net
neutron router-interface-add extnet_stackrouter stack_subnet_priv

neutron security-group-rule-create --protocol tcp --port-range-min 22 --port-range-max 22 default
neutron security-group-rule-create --protocol icmp default

subnet_id=$(neutron subnet-show stack_subnet_priv | grep network_id | awk '{print $4}')

nova boot --poll --flavor m1.tiny --image cirros --nic net-id=${subnet_id} --key-name demo_key --min-count 8 test0

for i in `seq 1 8`
do
   nova floating-ip-create ext_net
done


