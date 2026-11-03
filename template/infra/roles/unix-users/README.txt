Apply user changes to all hosts:
ansible-playbook site.yml -t users --check


Bootstrap server with "username" user and password:

1. Add new host to inventory "hosts.yml":

_group_:
  hosts:
    _host_node_:
      ansible_host: xx.xx.xx.xx

2. Add role for host to "site.yml":

- name: Host
  hosts: _host_node_
  roles:
  - os
  - { role: unix-users, tags: [users] }

3. Add required users on new server:

  To connect as root with password:
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook site.yml -l _host_node_ -t users \
  -e 'ansible_user=root' --ask-pass --check

  To connect as usual user with sudo and password:
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook site.yml -l _host_node_ -t users \
  -e 'ansible_user=_username_' --ask-pass --ask-become-pass --check

  To connect as root with a key:
ansible-playbook site.yml -l _host_node_ -t users -e 'ansible_user=root' --check

Run same command again without "--check".

4. Run full playbook as usual and auth with a key:
ansible-playbook site.yml -l _host_node_ --check
