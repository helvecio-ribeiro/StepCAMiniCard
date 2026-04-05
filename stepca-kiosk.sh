#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8089}"
DOCROOT="${DOCROOT:-/opt/stepca-kiosk}"
URL="${URL:-http://127.0.0.1:${PORT}/}"
CA_URL="${CA_URL:-https://127.0.0.1:8443}"
STEPCA_SERVICE="${STEPCA_SERVICE:-step-ca}"
STEPCA_CONFIG="${STEPCA_CONFIG:-/home/admin/.step/config/ca.json}"
ROOT_CERT="${ROOT_CERT:-/home/admin/.step/certs/root_ca.crt}"
ISSUED_DIR="${ISSUED_DIR:-/home/admin/issued}"
POLL_SECONDS="${POLL_SECONDS:-2}"
CHROMIUM_PROFILE_DIR="${CHROMIUM_PROFILE_DIR:-${DOCROOT}/chromium-profile}"

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\t'/ }"
  printf '%s' "${value}"
}

write_status() {
  local host_ip service_active health_ok latency_ms
  local stepca_version root_subject root_not_after tmp health_path
  local issued_count

  host_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  if [[ -z "${host_ip}" ]]; then
    host_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  host_ip="${host_ip:-unknown}"
  printf '%s\n' "${host_ip}" > "${DOCROOT}/ip.txt"

  service_active=false
  if systemctl is-active --quiet "${STEPCA_SERVICE}" 2>/dev/null; then
    service_active=true
  fi

  health_ok=false
  latency_ms=""
  health_path="${CA_URL%/}/health"
  tmp="$(curl -ksS -o /dev/null -w '%{http_code} %{time_total}' --max-time 2 "${health_path}" 2>/dev/null || true)"
  if [[ -n "${tmp}" ]]; then
    if [[ "${tmp%% *}" == "200" ]]; then
      health_ok=true
    fi
    latency_ms="$(printf '%s\n' "${tmp##* }" | awk '{printf "%.0fms", $1 * 1000}')"
  fi

  stepca_version="$(
    if command -v step-ca >/dev/null 2>&1; then
      step-ca version 2>/dev/null | head -n 1
    elif [[ -x /usr/bin/step-ca ]]; then
      /usr/bin/step-ca version 2>/dev/null | head -n 1
    fi
  )"
  stepca_version="$(printf '%s\n' "${stepca_version:-}" | sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
  stepca_version="${stepca_version:-not found}"

  root_subject=""
  root_not_after=""
  if [[ -f "${ROOT_CERT}" ]]; then
    root_subject="$(openssl x509 -in "${ROOT_CERT}" -noout -subject 2>/dev/null | sed 's/^subject=//')"
    root_not_after="$(openssl x509 -in "${ROOT_CERT}" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')"
  fi

  issued_count="0"
  if [[ -d "${ISSUED_DIR}" ]]; then
    issued_count="$(find "${ISSUED_DIR}" -maxdepth 1 -type f -name '*.key' | wc -l | awk '{print $1}')"
  fi

  cat > "${DOCROOT}/status.json.tmp" <<EOF
{
  "host_ip": "$(json_escape "${host_ip}")",
  "service_name": "$(json_escape "${STEPCA_SERVICE}")",
  "service_active": ${service_active},
  "ca_url": "$(json_escape "${CA_URL}")",
  "health_ok": ${health_ok},
  "health_latency_ms": "$(json_escape "${latency_ms}")",
  "stepca_version": "$(json_escape "${stepca_version}")",
  "issued_count": "$(json_escape "${issued_count}")",
  "config_path": "$(json_escape "${STEPCA_CONFIG}")",
  "root_cert_path": "$(json_escape "${ROOT_CERT}")",
  "root_subject": "$(json_escape "${root_subject}")",
  "root_not_after": "$(json_escape "${root_not_after}")"
}
EOF
  mv "${DOCROOT}/status.json.tmp" "${DOCROOT}/status.json"
}

collector_loop() {
  while true; do
    write_status || true
    sleep "${POLL_SECONDS}"
  done
}

if command -v xset >/dev/null 2>&1; then
  xset s off || true
  xset -dpms || true
  xset s noblank || true
fi

mkdir -p "${DOCROOT}"
mkdir -p "${CHROMIUM_PROFILE_DIR}"
write_status || true

cd "${DOCROOT}"
python3 -m http.server "${PORT}" --bind 127.0.0.1 &
SERVER_PID=$!
collector_loop &
COLLECTOR_PID=$!

cleanup() {
  kill "${COLLECTOR_PID}" 2>/dev/null || true
  kill "${SERVER_PID}" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

sleep 0.3

/usr/lib/chromium/chromium \
  --kiosk \
  --incognito \
  --no-first-run \
  --no-default-browser-check \
  --noerrdialogs \
  --disable-infobars \
  --overscroll-history-navigation=0 \
  --disable-gpu \
  --disable-gpu-compositing \
  --use-gl=swiftshader \
  --user-data-dir="${CHROMIUM_PROFILE_DIR}" \
  "${URL}" &
wait $!
