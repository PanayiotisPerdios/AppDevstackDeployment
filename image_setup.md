# Local Testing & OpenStack Deployment of DB + Web VM Images

## Prerequisites

- **Host** with QEMU & KVM (or use `-machine accel=tcg` if `/dev/kvm` is busy)  
- **cloud-image-utils** (for `cloud-localds`)  
- **libguestfs-tools** (for `virt-customize`)  
- **OpenStack** cloud & `openstack` CLI  
- **SSH** keypair on host (`~/.ssh/id_rsa` + `id_rsa.pub`)

---

## 1) Download & Prepare Base Images

1. **Download official Ubuntu Jammy Cloud Image**  
   ```bash
   wget https://cloud-images.ubuntu.com/jammy/20250516/jammy-server-cloudimg-amd64.img -O base-image.qcow2
    ```
2. Convert (if needed) & duplicate for DB/Web

```bash
# Install qemu-utils
sudo apt install qemu-utils
```

```bash
# Ensure QCOW2 format
qemu-img convert -f qcow2 -O qcow2 base-image.qcow2 base-image-fixed.qcow2
```
```bash
#Create two working images
cp base-image-fixed.qcow2 postgres-image.img
cp base-image-fixed.qcow2 springboot-image.img
cp base-image-fixed.qcow2 web-flask.img
```

## 1) Local QEMU Testing
### 1. Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y genisoimage cloud-image-utils libguestfs-tools qemu-system-x86 whois
```

### 2. Prepare `user-data.yml` & `meta-data-postgres.yml` & `meta-data-springboot.yml` & `user-data-springboot.yml`

#### user-data.yml

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
      spring.datasource.url=jdbc:postgresql://localhost:5432/BloodDonors
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
  - chown -R app:app /opt/app
  - |
    cat > /etc/systemd/system/app.service <<EOF
    [Unit]
    Description=Spring Boot App
    After=network.target

    [Service]
    User=app
    WorkingDirectory=/opt/app
    ExecStart=/usr/bin/java -jar /opt/app/target/*.jar --spring.config.location=file:/opt/app/application.properties
    SuccessExitStatus=143
    Restart=always
    Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

    [Install]
    WantedBy=multi-user.target
    EOF
  - systemctl daemon-reload
  - systemctl enable app.service
  - systemctl start app.service

```

#### meta-data-postgres.yml

```bash
instance-id: springboot-vm
local-hostname: springboot
```

### Generate the NoCloud seed disk:

### for web flask app
```bash
cloud-localds seed-web-flask.iso user-data.yaml
```

### 3. Launch & test the DB image
1. Resize postgres-image
```bash
qemu-img resize postgres-image.img +2G
```

1. Bake in postgres DB setup (optional):
```bash
sudo virt-customize -a postgres-image.img --firstboot scripts/./firstboot-postgres.sh
```
2. Launch the postgres DB VM:
```bash
qemu-system-x86_64 \
  -enable-kvm -m 2048 \
  -drive file=postgres-image.img,if=virtio,format=qcow2 \
  -drive file=seed-postgres.iso,if=virtio,format=raw \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::5432-:5432 \
  -device virtio-net,netdev=net0 \
  -nographic
```
### 4. Launch & test the Springboot image
1. Resize springboot-image
```bash
qemu-img resize springboot-image.img +2G
```
2. Bake in Springboot setup (optional):

```bash
sudo virt-customize -a springboot-image.img --firstboot scripts/./firstboot-springboot.sh
```
3. Launch the Springboot VM:
```bash
qemu-system-x86_64 \
  -enable-kvm -m 2048 \
  -drive file=springboot-image.img,if=virtio,format=qcow2 \
  -drive file=seed-postgres.iso,if=virtio,format=raw \
  -netdev user,id=net1,hostfwd=tcp::9090-:90,hostfwd=tcp::2223-:22 \
  -device virtio-net,netdev=net1 \
  -nographic
```
we gonna use the actual cloud-init config `user-data-springboot` later 

4. Cleanup the dummy cloud-init(making it look like it runs for the first time)
```bash
cloud-init clean --logs
```

### 5. Launch & test the Web image
1. Resize web-flask-image
```bash
qemu-img resize web-flask-image.img +1G
```
2. Bake in Web Flask setup:

```bash
sudo virt-customize -a web-flask-image.img --firstboot scripts/./firstboot-web-flask.sh
```
3. Launch the Web Flask VM:
```bash
qemu-system-x86_64 \
  -enable-kvm -m 2048 \
  -drive file=web-flask-image.img,if=virtio,format=qcow2 \
  -drive file=seed-web-flask.iso,if=virtio,format=raw \
  -netdev user,id=net1,hostfwd=tcp::8080-:80,hostfwd=tcp::2224-:22  \
  -device virtio-net,netdev=net1 \
  -nographic
```


### 6. SSH / HTTP into your VMs


### for springboot app

```bash
curl http://127.0.0.1:9090/
ssh -i ~/.ssh/id_rsa app@127.0.0.1 -p 2223
```

### for postgres db

```bash
ssh -i ~/.ssh/id_rsa app@127.0.0.1 -p 2222
psql -h localhost -U dbuser -d BloodDonors
```

### for web flask app

```bash
curl http://127.0.0.1:8080/
ssh -i ~/.ssh/id_rsa app@127.0.0.1 -p 2224
```

### 7. Set up SSH tunnel to postgresql vm

#### localy
```bash
ssh -i ~/.ssh/id_rsa -L 5432:localhost:5432 app@$FIP_DB
```

#### on devstack (postgres private_ip:10.0.0.XX, springboot floating_ip:192.168.56.YY )
```bash
ssh -L 5432:10.0.0.XX:5432 app@192.168.56.YY
```

#### Now you can connect locally to the database like this:

```bash
psql -h localhost -U dbuser -d BloodDonors
```


## 3) Upload & Launch on OpenStack

### 1. Upload to Glance
```bash
openstack image create --file postgres-image.img --disk-format qcow2 --container-format bare --public postgres-image
openstack image create --file springboot-image.img --disk-format qcow2 --container-format bare --public springboot-image
openstack image create --file web-flask-image.img --disk-format qcow2 --container-format bare --public web-flask-image
```

### 2. Launch Instances

### for springboot app

```bash
openstack server create \
  --flavor ds1G \
  --image springboot-image \
  --network web_private \
  --security-group springboot-sg \
  --key-name my-ssh-key \
  --user-data user-data-springboot.yaml \
  springboot-vm
```

### for postgres db

```bash
openstack server create \
  --flavor ds1G \
  --image postgres-image \
  --network web_private \
  --security-group postgres-sg \
  --key-name my-ssh-key \
  psql-vm
```

### for web flask app

```bash
openstack server create \
  --flavor m1.small \
  --image web-flask-image \
  --network web_private \
  --security-group web-flask-sg \
  --key-name my-ssh-key \
  web-flask-vm
```

### 3. Assign Floating IPs & Test

### for springboot app

```bash
FIP_DB=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip psql-vm $FIP_DB
ssh -i ~/.ssh/id_rsa app@$FIP_DB
```

### for postgres db

```bash
FIP_WEB=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip springboot-vm $FIP_WEB
curl http://$FIP_WEB/
```

### for web flask app

```bash
FIP_WEB=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip web-flask-vm $FIP_WEB
curl http://$FIP_WEB/
```
