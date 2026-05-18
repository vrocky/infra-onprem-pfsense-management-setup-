# Training VM Port-Forward Automation (Hybrid Discovery + Safety Gates)

This folder contains a production-oriented, easy-to-operate port-forward sync flow for training VMs.

It is designed to avoid manual VM inventory maintenance while keeping change safety controls.

---

## What This Does

- Discovers candidate training VMs from pfSense sources (ARP and DHCP leases).
- Applies safety gates before creating rules.
- Creates missing NAT port-forward rules idempotently.
- Optionally marks or removes stale auto-managed rules.
- Applies firewall changes only when create/delete operations occur.
- Exports mapping and run summary artifacts.

---

## Files

- `sync_training_vm_port_forward.py` - Main automation script
- `run-sync.ps1` - Simple operator wrapper
- `config.sample.json` - Configuration template
- `requirements.txt` - Python dependencies

---

## Quick Start

1. Install dependencies:

```powershell
cd .\training-vm-port-forward
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r .\requirements.txt
```

2. Create config:

```powershell
Copy-Item .\config.sample.json .\config.json
```

3. Set token:

```powershell
$env:PFSENSE_FW1_TOKEN = "<FW1_API_TOKEN>"
```

For Basic Auth mode (username/password), set:

```powershell
$env:PFSENSE_USERNAME = "admin"
$env:PFSENSE_PASSWORD = "password"
```

4. Validate config:

```powershell
.\run-sync.ps1 -Mode Validate
```

5. Dry-run discovery:

```powershell
.\run-sync.ps1 -Mode DryRun
```

6. Generate mapping only:

```powershell
.\run-sync.ps1 -Mode GenerateOnly
```

7. Apply reconciliation:

```powershell
.\run-sync.ps1 -Mode Apply
```

---

## Hybrid Safety Gates

Config section: `safety`

- `requireRecentLease`:
  - `true`: include only recent discovery records
- `minRecentMinutes`:
  - max age for discovery records to be considered active
- `allowUnknownLeaseAge`:
  - if `false`, entries without usable timestamp are excluded
- `checkTargetPortOpen`:
  - if `true`, validates target VM port (default target `3389`) before create
- `targetPortCheckTimeoutMs`:
  - timeout for target-port probe
- `staleRuleMode`:
  - `disabled`: no stale processing
  - `mark`: track stale candidates in state, no delete
  - `delete_after_grace`: delete stale managed rules after grace window
- `staleGraceMinutes`:
  - grace window before stale deletion

---

## Managed Rule Safety Model

Only rules with description prefix from `mapping.descriptionPrefix` are treated as managed for stale handling.

Recommended prefix:

- `AUTO_RDP_`

This prevents accidental mutation of manually managed NAT rules.

---

## Output Artifacts

Under `outputDir` (default `generated`):

- `training-rdp-nat-table.csv`
- `training-rdp-nat-table.md`
- `sync-summary.json`
- `runtime-state.json` (path configurable via `runtime.stateFile`)

---

## Suggested Production Rollout

1. Start with:
   - `staleRuleMode = "mark"`
   - `checkTargetPortOpen = false`
2. Run Validate -> DryRun -> GenerateOnly -> Apply.
3. Review mapping and summary outputs.
4. Enable target port check if needed.
5. Move to `delete_after_grace` only after stable operation.

---

## Endpoint Notes

Default config assumes API paths like:

- `GET /api/v1/firewall/nat/port_forward`
- `POST /api/v1/firewall/nat/port_forward`
- `DELETE /api/v1/firewall/nat/port_forward/{id}`
- `POST /api/v1/firewall/apply`

If your pfSense API package differs, update `config.json` endpoints and response field mappings.

---

## Authentication Modes

Config section: `api.auth`

- `mode = "token"`:
  - Uses bearer token from `tokenEnvVar`.
- `mode = "basic"`:
  - Uses username/password from either:
    - `username` + `password` in config (not recommended for shared repos), or
    - `usernameEnvVar` + `passwordEnvVar` environment variables (recommended).

Recommended local setup for your environment:

```powershell
$env:PFSENSE_USERNAME = "admin"
$env:PFSENSE_PASSWORD = "password"
```

