_samba_ensure_daemon() {
  # Only do anything if we're in proxy mode
  if [[ "${SAMBA_SCHED_BACKEND:-native}" != "proxy" ]]; then
    return 0
  fi

  # Where the IPC lives; must be visible to both host + container
  if [[ -z "${SAMBA_SCHED_DIR:-}" ]]; then
    SAMBA_SCHED_DIR="${HOME}/.samba_sched"
  fi
  export SAMBA_SCHED_DIR
  mkdir -p "${SAMBA_SCHED_DIR}"

  # Find the daemon binary (in PATH or in the repo)
  local daemon
  daemon="$(_samba_find_daemon || true)"

  if [[ -z "${daemon}" ]]; then
    echo "FATAL: SAMBA_SCHED_BACKEND=proxy but samba_sched_daemon not found." >&2
    echo "       Looked in PATH and in ${SAMBA_APPS_DIR}/samba_sched_wrappers/ and ${SAMBA_APPS_DIR}/SAMBA/samba_sched_wrappers/." >&2
    return 1
  fi

  # Check if it is already running
  local pid_file="${SAMBA_SCHED_DIR}/daemon.pid"
  local dpid=""
  if [[ -f "${pid_file}" ]]; then
    dpid="$(cat "${pid_file}" 2>/dev/null || true)"
  fi

  if [[ -n "${dpid}" && "${dpid}" =~ ^[0-9]+$ && kill -0 "${dpid}" 2>/dev/null ]]; then
    # Already running, nothing to do
    return 0
  fi

  echo "[sched] starting samba_sched_daemon as user ${USER}"
  echo "[sched] daemon=${daemon}"
  echo "[sched] dir=${SAMBA_SCHED_DIR}"

  # *** FIXED FLAG HERE ***
  nohup "${daemon}" --dir "${SAMBA_SCHED_DIR}" --backend slurm > "${SAMBA_SCHED_DIR}/daemon.log" 2>&1 &
  dpid=$!
  echo "${dpid}" > "${pid_file}"

  # Give it a moment and confirm it's alive
  sleep 0.1
  if ! kill -0 "${dpid}" 2>/dev/null; then
    echo "FATAL: samba_sched_daemon failed to start. See ${SAMBA_SCHED_DIR}/daemon.log" >&2
    return 1
  fi
}
