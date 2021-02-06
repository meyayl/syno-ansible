#!/bin/bash -eu
ansible_user=ansible
ansible_pass=ansible

function add_admin_user_and_fix_home_folder_permissions() {
  if [ $(sudo synouser --get "${ansible_user}" > /dev/null 2>&1; echo $?) -ne 0 ];then
    sudo synouser --add "${ansible_user}" "${ansible_pass}" "" 0 "" 0
    # get list of current users in group admistrators
    current_admins=$(sudo synogroup --get administrators | grep --perl-regexp --only-matching '(?<=^\d:\[).*(?=\]$)')
    admins=""
    for admin in ${current_admins};do
      admins="${admins} ${admin}"
    done
    
    sudo synogroup --member "administrators" ${admins} ${ansible_user} # only uses in group admistrators are allowd to login with key
    if [ $(sudo synogroup --get "ansible" > /dev/null 2>&1; echo $?) -ne 0 ];then
      sudo synogroup --add "ansible"
    fi
    sudo synogroup  --member "ansible" "${ansible_user}"
    user_dir=$(sudo synouser --get "${ansible_user}" | grep -oP '(?<=User.Dir(.){4}: \[).*(?=\])')
    until [ -d ${user_dir} ]; do sleep 1;done
    sudo chmod 700 "${user_dir}"
    sudo chown "${ansible_user}:users" -R "${user_dir}"
    if [ $(grep -E '/var/services/homes/${ansible_user}:/sbin/nologin' /etc/passwd > /dev/null 2>&1; echo $?) -eq 0 ];then
      sudo sed -ie 's#/var/services/homes/${ansible_user}:/sbin/nologin#/var/services/homes/${ansible_user}:/bin/sh#g' /etc/passwd
    fi
  fi
}

function add_sudoers() {
  sudo bash -c "[ ! -e /etc/sudoers.d/${ansible_user} ] && cat <<-SUDO > /etc/sudoers.d/${ansible_user}
    ${ansible_user} ALL=(ALL) NOPASSWD: ALL
SUDO" || true
}

function create_key_and_copy_to_home_folder() {
  force_copy_key=false
  # subfolder of current user's folder
  if [ ! -e ssh/id_rsa ];then 
    mkdir -p ssh
    ssh-keygen -q -b 4096 -t ed25519 -N ""  -f ssh/id_rsa
    sudo chmod 700 "ssh"
    sudo chmod 600 "ssh/id_rsa"
    sudo chmod 600 "ssh/id_rsa.pub"
    force_copy_key=true
  fi

  # homedir of ansible user
  user_dir=$(sudo synouser --get ${ansible_user} | grep -oP '(?<=User.Dir(.){4}: \[).*(?=\])')
  if [ ! -e "${user_dir}/.ssh/authorized_keys" ] || [ "${force_copy_key}" == "true" ];then
    sudo mkdir -p "${user_dir}/.ssh"
    sudo chmod 777 "${user_dir}"
    sudo chmod 777 -R "${user_dir}/.ssh/"
    sudo cat "ssh/id_rsa.pub" > "${user_dir}/.ssh/authorized_keys"
    sudo chmod 700 "${user_dir}"
    sudo chmod 700 "${user_dir}/.ssh/"
    sudo chmod 600 "${user_dir}/.ssh/authorized_keys"
    sudo chown "${ansible_user}:users" -R "${user_dir}/"
  fi
}

function create_ansible_inventory() {
  cat <<-EOF > inventory
[all]
${HOSTNAME}

[all:vars]
ansible_user=${ansible_user}
EOF
}

function create_ansible_cfg() {
  cat <<-CFG > ansible.cfg
[defaults]
strategy_plugins  = /usr/lib/python3.6/site-packages/ansible_mitogen/plugins/strategy
strategy          = mitogen_linear
host_key_checking = False
CFG
}

function start_ansible_container() {
  docker run -ti --rm \
    -e USER=ansible \
    -e UID=$(id -u) \
    -v ${PWD}/ssh/:/home/ansible/.ssh/ \
    -v ${PWD}:/data cytopia/ansible:2.8-tools \
    ansible-playbook playbook -i inventory
}

function sanity_check() {
  if [ $(id -u) -eq 0 ];then
    echo "Do not run this script as root user, it will use sudo where ever root priviliges are required!"
    exit 1
  fi
  if [ "${PWD}" == "~" ];then
    echo "Do not run this script directly in the user's homefolder. It needs to be run inside a subfolder"
    exit 1
  fi
  set +e
  user_data=$(sudo synouser --get ${ansible_user})
  set -e
  if [ $(echo "${user_data}" | grep -wc 'SynoErr') -eq 1 ];then
    echo "user ${ansible_user} does not exist, will create it!"
  elif [ $(echo "${user_data}" | grep -E -wc '\([[:digit:]]*\) ansible') -eq 1 ];then
    echo "user ${ansible_user} exists and is in ansible group. Everything is fine"
  else
    echo "user ${ansible_user} is not in ansible group. Did you try to use an existing account? Don't!"
    exit 1
  fi
}

function main(){
  sanity_check
  add_admin_user_and_fix_home_folder_permissions
  add_sudoers
  create_key_and_copy_to_home_folder
  create_ansible_inventory
  create_ansible_cfg
  start_ansible_container
}

main
