# step-ca Kiosk Health Card (systemd)

This bundle runs a local `step-ca` status dashboard in Chromium kiosk mode on a Raspberry Pi or other small Linux host.

It is designed after the `PiHoleMiniCard` project, but adapted for Smallstep `step-ca`.

This project is not `step-ca` itself. You must install and configure `step-ca` first.

It starts:

1. A local status collector loop that writes `status.json`
2. `python3 -m http.server` serving `/opt/stepca-kiosk` on `127.0.0.1:8089`
3. Chromium in kiosk mode pointing at `http://127.0.0.1:8089/`

The kiosk shows:

- service state for `step-ca`
- `https://<host>:8443/health` status
- listener state on the CA port
- detected host IP
- `step-ca` version
- issued certificate count derived from `*.key` files in `/home/admin/issued`
- most recently issued certificate name and timestamp
- root certificate subject and expiration when available

## Install (Raspberry Pi OS Desktop)

1. Install dependencies:

```bash
sudo apt update
sudo apt -y install chromium python3 curl openssl iproute2
```

2. Copy files to `/opt/stepca-kiosk`:

```bash
sudo mkdir -p /opt/stepca-kiosk
sudo cp index.html stepca-kiosk.sh stepca-kiosk.service /opt/stepca-kiosk/
sudo chmod +x /opt/stepca-kiosk/stepca-kiosk.sh
sudo chown -R admin:admin /opt/stepca-kiosk
```

3. Install the systemd service:

```bash
sudo cp stepca-kiosk.service /etc/systemd/system/stepca-kiosk.service
```

If your Linux username is not `admin`, edit the service before enabling it:

- `User=`
- `Group=`
- `XAUTHORITY=/home/<user>/.Xauthority`

Also adjust these environment variables if needed:

- `CA_URL`
- `STEPCA_SERVICE`
- `STEPCA_CONFIG`
- `ROOT_CERT`
- `DOCROOT`

Then enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now stepca-kiosk.service
```

## Default assumptions

The kiosk defaults assume:

- `step-ca` health endpoint: `https://127.0.0.1:8443/health`
- service name: `step-ca`
- config path: `/home/admin/.step/config/ca.json`
- root cert path: `/home/admin/.step/certs/root_ca.crt`

Override those in the systemd unit if your install differs.

## Manage

```bash
sudo systemctl status stepca-kiosk
sudo systemctl restart stepca-kiosk
sudo journalctl -u stepca-kiosk -f --no-pager
```

## Uninstall

```bash
sudo systemctl disable --now stepca-kiosk
sudo rm -f /etc/systemd/system/stepca-kiosk.service
sudo systemctl daemon-reload
sudo rm -rf /opt/stepca-kiosk
```
