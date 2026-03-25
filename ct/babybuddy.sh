#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/maziggy/bambuddy

APP="Bambuddy"
var_tags="${var_tags:-cloud}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/bambuddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_info "Updating Bambuddy"
  cd /opt/bambuddy
  $STD docker compose pull
  $STD docker compose up -d
  msg_ok "Updated ${APP} LXC"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_info "Installing Docker"
$STD apt-get update
$STD apt-get install -y ca-certificates curl gnupg
$STD install -m 0755 -d /etc/apt/keyrings
$STD curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
$STD chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $VERSION_CODENAME stable" >/etc/apt/sources.list.d/docker.list
$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
$STD systemctl enable --now docker

msg_info "Deploying Bambuddy"
$STD mkdir -p /opt/bambuddy
cd /opt/bambuddy
$STD curl -fsSL https://raw.githubusercontent.com/maziggy/bambuddy/main/docker-compose.yml -o docker-compose.yml
$STD docker compose up -d

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
