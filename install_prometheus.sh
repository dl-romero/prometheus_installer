#!/bin/bash
set -euo pipefail

PROM_VERSION="2.54.0"
PROM_TARBALL="prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
PROM_DIR="prometheus-${PROM_VERSION}.linux-amd64"
TMP_DIR="/tmp"
INSTALL_DIR="${TMP_DIR}/prometheus"

enable_auth="Y"
prom_user="promethueus"
prom_pass="promethueus"
configure_firewall="N"
configure_selinux="N"
non_interactive=0

normalize_yn() {
	local value="${1:-}"
	case "${value}" in
		y|Y|yes|YES|Yes|true|TRUE|1)
			echo "Y"
			;;
		n|N|no|NO|No|false|FALSE|0)
			echo "N"
			;;
		*)
			echo "Invalid yes/no value: ${value}" >&2
			exit 1
			;;
	esac
}

usage() {
	cat <<EOF
Usage: $0 [options]

Options:
  --non-interactive         Run without prompts using defaults/flags.
  --auth <yes|no>           Enable or disable web basic auth (default: yes).
  --auth-user <username>    Basic auth username (default: promethueus).
  --auth-pass <password>    Basic auth password (default: promethueus).
  --firewall <yes|no>       Configure firewalld to allow 9090/tcp (default: no).
  --selinux <yes|no>        Configure SELinux port policy for 9090 (default: no).
  --help                    Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--non-interactive)
			non_interactive=1
			shift
			;;
		--auth)
			enable_auth="$(normalize_yn "${2:-}")"
			shift 2
			;;
		--auth-user)
			prom_user="${2:-}"
			shift 2
			;;
		--auth-pass)
			prom_pass="${2:-}"
			shift 2
			;;
		--firewall)
			configure_firewall="$(normalize_yn "${2:-}")"
			shift 2
			;;
		--selinux)
			configure_selinux="$(normalize_yn "${2:-}")"
			shift 2
			;;
		--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			usage
			exit 1
			;;
	esac
done

if [[ "${EUID}" -ne 0 ]]; then
	echo "Please run this script as root (sudo)."
	exit 1
fi

if [[ "${non_interactive}" -eq 0 ]]; then
	read -r -p "Enable Prometheus web basic authentication? (Y/n): " enable_auth_input
	enable_auth_input=${enable_auth_input:-Y}
	enable_auth="$(normalize_yn "${enable_auth_input}")"
fi

if [[ "${enable_auth}" =~ ^[Yy]$ ]]; then
	if ! command -v htpasswd >/dev/null 2>&1; then
		echo "Installing httpd-tools for bcrypt password generation..."
		yum install -y httpd-tools
	fi

	if [[ "${non_interactive}" -eq 0 ]]; then
		read -r -p "Prometheus username [${prom_user}]: " prom_user_input
		prom_user=${prom_user_input:-${prom_user}}

		read -r -s -p "Prometheus password [default hidden]: " prom_pass_input
		echo
		if [[ -n "${prom_pass_input}" ]]; then
			read -r -s -p "Confirm password: " prom_pass_confirm
			echo

			if [[ "${prom_pass_input}" != "${prom_pass_confirm}" ]]; then
				echo "Passwords do not match. Exiting."
				exit 1
			fi
			prom_pass="${prom_pass_input}"
		fi
	fi

	if [[ -z "${prom_user}" || -z "${prom_pass}" ]]; then
		echo "Username and password cannot be empty when auth is enabled."
		exit 1
	fi
fi

cd "${TMP_DIR}"
yum update -y
yum install -y wget tar
wget -O "${PROM_TARBALL}" "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TARBALL}"

if ! id prometheus >/dev/null 2>&1; then
	useradd --no-create-home --shell /bin/false prometheus
fi

mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

rm -rf "${INSTALL_DIR}"
tar -xzf "${PROM_TARBALL}"
mv -f "${PROM_DIR}" "${INSTALL_DIR}"

cp "${INSTALL_DIR}/prometheus" /usr/local/bin/
cp "${INSTALL_DIR}/promtool" /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

cp -r "${INSTALL_DIR}/consoles" /etc/prometheus
cp -r "${INSTALL_DIR}/console_libraries" /etc/prometheus
cp "${INSTALL_DIR}/prometheus.yml" /etc/prometheus/prometheus.yml
chown -R prometheus:prometheus /etc/prometheus

if [[ "${non_interactive}" -eq 0 ]]; then
	read -r -p "Configure firewalld to allow 9090/tcp? (y/N): " fw_input
	fw_input=${fw_input:-N}
	configure_firewall="$(normalize_yn "${fw_input}")"

	read -r -p "Configure SELinux policy for Prometheus port 9090? (y/N): " selinux_input
	selinux_input=${selinux_input:-N}
	configure_selinux="$(normalize_yn "${selinux_input}")"
fi

if [[ "${configure_firewall}" =~ ^[Yy]$ ]]; then
	if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
		firewall-cmd --permanent --add-port=9090/tcp
		firewall-cmd --reload
		echo "Firewalld configured for 9090/tcp."
	else
		echo "Skipping firewalld configuration: firewalld is not available or not running."
	fi
fi

if [[ "${configure_selinux}" =~ ^[Yy]$ ]]; then
	if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
		if ! command -v semanage >/dev/null 2>&1; then
			yum install -y policycoreutils-python-utils || yum install -y policycoreutils-python
		fi
		if command -v semanage >/dev/null 2>&1; then
			semanage port -a -t http_port_t -p tcp 9090 2>/dev/null || semanage port -m -t http_port_t -p tcp 9090
			echo "SELinux policy updated for tcp/9090."
		else
			echo "Skipping SELinux configuration: semanage is not available."
		fi
	else
		echo "Skipping SELinux configuration: SELinux is disabled or unavailable."
	fi
fi

if [[ "${enable_auth}" =~ ^[Yy]$ ]]; then
	# Prometheus expects bcrypt-hashed credentials in web config.
	bcrypt_hash="$(printf '%s\n' "${prom_pass}" | htpasswd -niBC 12 "${prom_user}" | cut -d: -f2)"
	cat >/etc/prometheus/web.yml <<EOF
basic_auth_users:
  ${prom_user}: ${bcrypt_hash}
EOF
else
	cat >/etc/prometheus/web.yml <<EOF
{}
EOF
fi

unset prom_pass prom_pass_confirm prom_pass_input

chmod 640 /etc/prometheus/web.yml
chown prometheus:prometheus /etc/prometheus/web.yml

cp prometheus.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now prometheus
systemctl status prometheus --no-pager

echo "Installation completed."
if [[ "${enable_auth}" =~ ^[Yy]$ ]]; then
	echo "Prometheus is protected with username/password."
	if [[ "${prom_user}" == "promethueus" ]]; then
		echo "Using default credentials (promethueus/promethueus). Change these for production use."
	fi
else
	echo "Prometheus authentication is disabled."
fi