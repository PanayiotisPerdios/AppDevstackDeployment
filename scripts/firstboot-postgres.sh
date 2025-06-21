#!/bin/bash
apt-get update
apt-get install -y postgresql-14 postgresql-client-14
sed -i "s/#listen_addresses = .*/listen_addresses = '*'/" /etc/postgresql/14/main/postgresql.conf
echo "host all all 0.0.0.0/16 md5" >> /etc/postgresql/14/main/pg_hba.conf
systemctl daemon-reexec
systemctl enable postgresql
systemctl start postgresql
systemctl enable ssh
systemctl start ssh
sudo -u postgres psql -c "CREATE DATABASE \"BloodDonors\";"
sudo -u postgres psql -c "CREATE USER dbuser WITH PASSWORD 'pass123';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"BloodDonors\" TO dbuser;"
