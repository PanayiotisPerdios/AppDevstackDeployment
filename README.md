# Local Testing & OpenStack Deployment of DB + Web VM Images

## Prerequisites

- **Host** with QEMU & KVM (or use `-machine accel=tcg` if `/dev/kvm` is busy)  
- **cloud-image-utils** (for `cloud-localds`)  
- **libguestfs-tools** (for `virt-customize`)  
- **OpenStack** cloud & `openstack` CLI  
- **SSH** keypair on host (`~/.ssh/id_rsa` + `id_rsa.pub`)

---

## Part 0: Download & Prepare Base Images

1. **Download official Ubuntu Jammy Cloud Image**  
   ```bash
   wget https://cloud-images.ubuntu.com/jammy/20250429/jammy-server-cloudimg-amd64.img \
     -O base-image.qcow2
    ```
2. Convert (if needed) & duplicate for DB/Web
```bash
# Ensure QCOW2 format
qemu-img convert -f qcow2 -O qcow2 base-image.qcow2 base-image-fixed.qcow2
```
```bash
#Create two working images
cp base-image-fixed.qcow2 postgres-image.img
cp base-image-fixed.qcow2 springboot-image.img
```

## Part I: Local QEMU Testing
### 1. Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y genisoimage cloud-image-utils libguestfs-tools qemu-system-x86
```

### 2. Prepare `user-data-postgres.yml` & `meta-data-springboot.yml` & `user-data-springboot.yml`

#### user-data-postgres.yml

```bash
#cloud-config
users:
  - name: app
    ssh-authorized-keys:
      - ssh-rsa AAAA…your_public_key… app@host
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash

package_update: true
package_upgrade: true
```

#### user-data-springboot.yml
```bash
#cloud-config
users:
  - name: app
    ssh-authorized-keys:
      - ssh-rsa AAAA…your_public_key… app@host
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash

package_update: true
package_upgrade: true

write_files:
  - path: /opt/app/src/main/resources/application.properties
    content: |
      server.port=9090
      spring.datasource.url=jdbc:postgresql://10.0.2.15:5432/BloodDonors
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

runcmd:
  - systemctl restart app.service

```

#### meta-data-postgres.yml

```bash
instance-id: springboot-vm
local-hostname: springboot
```

### Generate the NoCloud seed disk:

### for postgres db
#### with genisoimage:
```bash
genisoimage -output seed_springboot.iso -volid cidata -joliet -rock user-data-springboot.yaml meta-data-springboot.yaml
```
#### with cloud-localds
```bash
cloud-localds seed_springboot.iso user-data-springboot.yaml meta-data-springboot.yaml
```

### for springboot app 
#### with genisoimage:
```bash
genisoimage -output seed_postgres.iso -volid cidata -joliet -rock user-data-postgres.yaml
```
#### with cloud-localds
```bash
cloud-localds seed_postgres.iso user-data-postgres.yaml 
```
### 3. Launch & test the DB image

1. Bake in postgres DB setup (optional):
```bash
virt-customize -a sql-image.img --firstboot-command '
  apt-get update &&
  apt-get install -y postgresql-14 postgresql-client-14 &&
  sed -i "s/#listen_addresses = .*/listen_addresses = '\''*'\''/" /etc/postgresql/14/main/postgresql.conf &&
  echo "host all all 0.0.0.0/16 md5" >> /etc/postgresql/14/main/pg_hba.conf &&
  systemctl daemon-reexec &&
  systemctl enable postgresql &&
  systemctl start postgresql &&
  systemctl enable ssh &&
  systemctl start ssh &&
  sudo -u postgres psql <<EOF
CREATE DATABASE "BloodDonors";
CREATE USER dbuser WITH PASSWORD '\''pass123'\'';
GRANT ALL PRIVILEGES ON DATABASE "BloodDonors" TO dbuser;
EOF
'
```
2. Launch the postgres DB VM:
```bash
qemu-system-x86_64 \
  -enable-kvm -m 2048 \
  -drive file=postgres-image.img,if=virtio,format=qcow2 \
  -drive file=seed.iso,if=virtio,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net,netdev=net0 \
  -nographic
```
### 4. Launch & test the Web image
1. Bake in Web setup (optional):

```bash
virt-customize -a springboot-image.img --firstboot-command '
  apt-get update &&
  apt-get install -y openjdk-17-jdk maven git &&
  git clone https://github.com/JohnSkouloudis/BloodDonorApp-Backend.git /opt/app &&
  cd /opt/app &&
  mvn clean install &&
  cat > /etc/systemd/system/app.service <<EOF
[Unit]
Description=Spring Boot App
After=network.target
[Service]
WorkingDirectory=/opt/app
ExecStart=/usr/bin/mvn spring-boot:run
Restart=always
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
[Install]
WantedBy=multi-user.target
EOF &&
  systemctl daemon-reload
'
```
2. Launch the Web VM:
```bash
qemu-system-x86_64 \
  -enable-kvm -m 2048 \
  -drive file=springboot-image.img,if=virtio,format=qcow2 \
  -drive file=seed.iso,if=virtio,format=raw \
  -netdev user,id=net1,hostfwd=tcp::9090-:90 \
  -device virtio-net,netdev=net1 \
  -nographic
```

### 5. SSH / HTTP into your VMs
```bash
ssh -i ~/.ssh/id_rsa app@127.0.0.1 -p 2222
```

```bash
curl http://127.0.0.1:9090/
```

## Part II: Upload & Launch on OpenStack

### 1. Upload to Glance
```bash
openstack image create --disk-format qcow2 --container-format bare --public postgres-image.img
openstack image create --disk-format qcow2 --container-format bare --public springboot-image.img
```

### 2. Launch Instances
```bash
openstack server create --flavor m1.small \
  --image postgres-image --network app_net db-vm

openstack server create --flavor m1.small \
  --image springboot-image --network app_net web-vm
```
### 3. Assign Floating IPs & Test
```bash
FIP_DB=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip db-vm $FIP_DB
ssh -i ~/.ssh/id_rsa app@$FIP_DB

FIP_WEB=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip web-vm $FIP_WEB
curl http://$FIP_WEB/
