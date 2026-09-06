systemctl is-active nginx
systemctl is-enabled nginx
systemctl is-active tex-auth.service
systemctl is-enabled tex-auth.service

sudo ss -ltnp | grep -E ':8000|:80|:443'
curl --fail-with-body http://127.0.0.1/openapi.json >/dev/null
