sudo ln -s \
  /etc/nginx/sites-available/texnote-p1 \
  /etc/nginx/sites-enabled/texnote-p1

sudo unlink /etc/nginx/sites-enabled/default

sudo nginx -t
