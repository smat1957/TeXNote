systemctl status tex-auth.service --no-pager -l
systemctl is-enabled tex-auth.service
systemctl is-active tex-auth.service
ss -ltnp | grep -E ':8000|:80|:443'
