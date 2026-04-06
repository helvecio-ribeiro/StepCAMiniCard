# step-ca Kiosk Health Card (systemd)

This bundle runs a local `step-ca` status dashboard in Chromium kiosk mode on a Raspberry Pi or other small Linux host.

It is designed after the `PiHoleMiniCard` project, but adapted for Smallstep `step-ca`.

This project is not `step-ca` itself. You must install and configure `step-ca` first.

## Brief `step-ca` install

This kiosk expects `step-ca` to already be installed and running on the same host.

Typical high-level flow on the PKI server:

1. Install `step` and `step-ca`.
2. Initialize the CA:

```bash
step ca init
```

3. Run `step-ca` as a systemd service using your `ca.json` and password file.
4. Confirm it is listening and healthy:

```bash
sudo ss -lntp | grep step-ca
curl -k https://127.0.0.1:8443/health
```

Expected health response:

```json
{"status":"ok"}
```

Common paths used by this kiosk:

- config: `/home/admin/.step/config/ca.json`
- root cert: `/home/admin/.step/certs/root_ca.crt`
- issued cert/key outputs: `/home/admin/issued`

If you need the full PKI setup procedure, see your local deployment notes for `step-ca`.

It starts:

1. A local status collector loop that writes `status.json`
2. `python3 -m http.server` serving `/opt/stepca-kiosk` on `127.0.0.1:8089`
3. Chromium in kiosk mode pointing at `http://127.0.0.1:8089/`

The kiosk shows:

- detected host IP in the header
- overall health pill
- `step-ca` systemd state
- `https://127.0.0.1:8443/health` status and latency
- root certificate subject and expiration
- `step-ca` version
- issued certificate count derived from `*.key` files in `/home/admin/issued`

Current V1 layout:

- top tiles: `Systemd`, `Health`
- lower detail rows: `CA URL`, `Root subject`, `Root expires`, `Version`, `Issued`

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
- `ISSUED_DIR`
- `CHROMIUM_PROFILE_DIR`
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
- issued cert/key directory: `/home/admin/issued`
- isolated Chromium profile: `/opt/stepca-kiosk/chromium-profile`

Override those in the systemd unit if your install differs.

## Manage

```bash
sudo systemctl status stepca-kiosk
sudo systemctl restart stepca-kiosk
sudo journalctl -u stepca-kiosk -f --no-pager
```

Useful validation commands on the PKI host:

```bash
sudo systemctl status step-ca --no-pager
sudo ss -lntp | grep step-ca
curl -k https://127.0.0.1:8443/health
ls -l /home/admin/issued/*.key
```

If Chromium fails with a profile lock error, this project already supports an isolated kiosk profile:

```bash
sudo systemctl edit stepca-kiosk
```

Then set or confirm:

```ini
[Service]
Environment=CHROMIUM_PROFILE_DIR=/opt/stepca-kiosk/chromium-profile
```

Apply it with:

```bash
sudo systemctl daemon-reload
sudo systemctl restart stepca-kiosk
```

## Uninstall

```bash
sudo systemctl disable --now stepca-kiosk
sudo rm -f /etc/systemd/system/stepca-kiosk.service
sudo systemctl daemon-reload
sudo rm -rf /opt/stepca-kiosk
```
