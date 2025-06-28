#!/bin/bash

# Update and install necessary packages
apt-get update
apt-get install -y nginx python3 python3-pip

# Install Flask
pip3 install flask

# Create application directory
mkdir -p /opt/app

# Create a basic Flask app
cat > /opt/app/app.py <<EOF
from flask import Flask
app = Flask(__name__)
@app.route("/")
def hello():
    return "Hello from Web VM"
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

# Create systemd service for Flask app
cat > /etc/systemd/system/app.service <<EOF
[Unit]
Description=Flask App
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable app.service
systemctl enable nginx

# Start services
systemctl start app.service
systemctl start nginx
