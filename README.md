# prometheus_installer
For Redhat based Operating systems only Ex: Redhat (RHEL), CentOS, Rocky, Fedora.<BR>
This script will download prometheus and complete the installation and start the service.

## What this installer now configures
- Installs Prometheus v2.54.0 binaries and default config.
- Creates and configures the `prometheus` system user and required directories.
- Installs and enables the systemd service.
- Enables lifecycle and admin API flags in Prometheus.
- Supports config reload via `systemctl reload prometheus`.
- Enables web basic auth by default (username/password prompt).
- Optional firewalld and SELinux port policy setup for `9090/tcp`.

#### Installation Instructions
```
cd /tmp
wget https://github.com/dl-romero/prometheus_installer/archive/refs/heads/main.zip
unzip prometheus_installer-main.zip
cd prometheus_installer-main
sudo chmod 777 install_prometheus.sh
sudo ./install_prometheus.sh
```

### Non-interactive mode
You can run the installer without prompts:

```bash
sudo ./install_prometheus.sh --non-interactive --auth yes --auth-user admin --auth-pass 'strong-password' --firewall yes --selinux yes
```

### Manage Prometheus Basic-Auth Users
Use the helper script to add, remove, update, or list users in `/etc/prometheus/web.yml`:

```bash
sudo chmod +x manage_prometheus_users.sh

# Add user (prompts for password)
sudo ./manage_prometheus_users.sh add alice --reload

# Update password (non-interactive)
sudo ./manage_prometheus_users.sh update alice 'new-strong-password' --reload

# Remove user
sudo ./manage_prometheus_users.sh remove alice --reload

# List users
sudo ./manage_prometheus_users.sh list
```

## Notes
- If you enable auth, the installer creates `/etc/prometheus/web.yml` with a bcrypt-hashed password.
- If you disable auth, `/etc/prometheus/web.yml` is created as an empty config.
- Default auth credentials are `promethueus` / `promethueus` unless you override them.
- After changing `/etc/prometheus/prometheus.yml`, run:

```
sudo systemctl reload prometheus
```
