#!/bin/bash

echo "[1/8] Installing required packages..."
apt-get update
apt-get install -y openjdk-17-jdk maven git openssh-server postgresql-14 postgresql-client-14 netcat

echo "[2/8] Ensuring SSH is enabled..."
systemctl daemon-reexec
systemctl enable ssh
systemctl start ssh

echo "[3/8] Creating app user if it doesn't exist..."
id -u app &>/dev/null || useradd -m -s /bin/bash app

echo "[4/8] Cloning project repository..."
git clone https://github.com/JohnSkouloudis/BloodDonorApp-Backend.git /opt/springboot

echo "[5/8] Creating application.properties..."
rm /opt/springboot/src/main/resources/application.properties
touch /opt/springboot/src/main/resources/application.properties    
cat > /opt/springboot/src/main/resources/application.properties <<EOF
server.port=9090
spring.datasource.url=jdbc:postgresql://10.0.0.61:5432/BloodDonors?sslmode=disable
spring.datasource.username=dbuser
spring.datasource.password=pass123
spring.jpa.generate-ddl=true
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
app.jwtSecret=123esef
app.jwtExpirationMs=86400000
frontend.ip=http://vuejs:9000
management.endpoint.health.probes.enabled=true
management.health.livenessState.enabled=true
management.health.readinessState.enabled=true
EOF

echo "[6/8] Setting ownership..."
chown -R app:app /opt/springboot

echo "[7/8] Building Spring Boot application..."
cd /opt/springboot
mvn clean package -DskipTests
rm -rf .git

echo "[8/8] Creating and starting systemd service..."
cat > /etc/systemd/system/app.service <<EOF
[Unit]
Description=Spring Boot App
After=network.target
Wants=network-online.target
After=postgresql.service
StartLimitIntervalSec=0

[Service]
User=app
WorkingDirectory=/opt/springboot
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Wait for DB
ExecStartPre=/bin/bash -c 'until nc -z 10.0.0.61 5432; do echo "Waiting for DB..."; sleep 2; done'

ExecStart=/usr/bin/java -jar /opt/springboot/target/BloodDonorApp-0.0.1-SNAPSHOT.jar --spring.config.location=file:/opt/springboot/src/main/resources/application.properties
SuccessExitStatus=143
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable app.service
systemctl start app.service
