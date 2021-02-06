# Synology Ansible

This project aims to bring Ansible to your Synology NAS.

It will create the required user account permitted to login to your NAS via ssh keybased authentification.
And of course run ansible playbooks using this user account.

The script is ment to be executed with an admin useraccount (though not as root!)
It will sudo inside the script, whenever root permissions are required.

Make sure to either let the `ansible_user` stay as `ansible` or use any not yet existing username for it!

## How to use
1. clone git project
2. edit variable `ansible_user` and `ansible_pass` in `ansible.sh`
3. execute `./ansible.sh`

If the included test playbook works fine, you can start to add your own playbooks and roles to the folder.

## What does the script step do?
Basicly it creates and configures everything required to run Ansible on your NAS:
1. perform sanity checks (required to make sure the script does not unintended things on your NAS)
2. add new admin user for ansible and fix home folder permissions (necessary for keybased-auth)
3. add ansible user to sudoers (necessary to become root in the playbooks)
4. creates a ssh key for ansible user and copies it into its home folder (necessary for keybased-auth)
5. creates the ansible inventory (necessary to know how to context the NAS)
6. creates the ansible.cfg with mitogen enabled (nice to have  performance booster)
7. starts ansible in a docker container
