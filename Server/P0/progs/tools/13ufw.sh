sudo apt update
sudo apt install ufw

sudo ufw allow from 192.168.3.0/24 to any port 22 proto tcp
sudo ufw allow from 192.168.3.0/24 to any port 80 proto tcp

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw deny 8000/tcp

sudo ufw enable
sudo ufw status numbered
