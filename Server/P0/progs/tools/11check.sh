sudo systemctl daemon-reload
sudo systemctl restart tex-auth.service

systemctl status tex-auth.service --no-pager -l
journalctl -u tex-auth.service -n 100 --no-pager

sudo ss -ltnp | grep -E ':8000|:80|:443'
