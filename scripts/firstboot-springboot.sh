#!/bin/bash

set -e

apt-get update
apt-get install -y openjdk-17-jdk maven git

# Create app user if not exists
id -u app &>/dev/null || useradd -m -s /bin/bash app

# Clone the Spring Boot app and build project
git clone https://github.com/JohnSkouloudis/BloodDonorApp-Backend.git /opt/app
cd /opt/app
mvn clean package -DskipTests

rm -rf .git

# Set ownership
chown -R app:app /opt/app
