#!/usr/bin/env bash
set -Eeuo pipefail

deployment_user="${1:?Usage: deploy-ec2.sh ubuntu}"
if [[ "$deployment_user" != "ubuntu" ]]; then
    echo "This deployment script requires the Ubuntu AMI's ubuntu user." >&2
    exit 1
fi

app_dir="/opt/chat-app"
environment_file="/home/${deployment_user}/chat-app.env"

cleanup() {
    rm -f "$environment_file" /tmp/chat-deploy-ec2.sh
}
trap cleanup EXIT

if [[ ! -s "$environment_file" ]]; then
    echo "The uploaded application environment file is missing or empty." >&2
    exit 1
fi

chmod 600 "$environment_file"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git docker.io docker-compose-v2
systemctl enable --now docker

install -d -o "$deployment_user" -g "$deployment_user" "$app_dir"
if [[ -d "${app_dir}/.git" ]]; then
    runuser -u "$deployment_user" -- git -C "$app_dir" fetch --depth 1 origin main
    runuser -u "$deployment_user" -- git -C "$app_dir" checkout -B main origin/main
else
    runuser -u "$deployment_user" -- git clone --depth 1 --branch main \
        https://github.com/Nizamuddin8053/chat.git "$app_dir"
fi

install -o "$deployment_user" -g "$deployment_user" -m 600 \
    "$environment_file" "${app_dir}/.env"
cd "$app_dir"
docker compose down --remove-orphans
docker compose up -d --build --remove-orphans

for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error http://127.0.0.1:5001/health >/dev/null; then
        echo "Backend health check passed."
        exit 0
    fi
    sleep 10
done

echo "The backend did not become healthy within five minutes." >&2
docker compose ps
exit 1
