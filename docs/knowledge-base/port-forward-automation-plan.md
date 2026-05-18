# Training VM API Port-Forward Automation Plan

**Status:** Draft for review before full rollout  
**Date:** 2026-05-03  
**Scope:** Training VMs on `192.168.50.0/24`

---

## Goal

Implement repeatable, idempotent API-based port-forward management for training VMs so that:

- New/active training VMs get predictable RDP port forwards.
- Existing rules are not duplicated.
- Optional stale-rule cleanup can be enabled safely later.
- Changes are applied in a controlled way with dry-run first.

---

## Chosen Approach

Use the existing Python automation in `port-forward-sync/` as the primary rollout path.

Why this path:

- Already supports discovery, create, optional stale cleanup, and apply.
- Config-driven endpoints and payload fields (portable across API variants).
- Produces mapping tables (`csv` and `md`) for operations visibility.

---

## Inventoryless Automation Options

This section documents ways to avoid manual training VM inventory maintenance.

### Option 1: pfSense Dynamic Discovery Only (Recommended)

Source of truth:

- pfSense ARP table
- pfSense DHCP leases
- Training interface + training subnet filters

How it works:

1. Discover active client IPs from configured pfSense endpoints.
2. Filter to training subnet (`192.168.50.0/24`).
3. Build deterministic WAN-to-VM mapping from IP suffix.
4. Reconcile rules idempotently (create missing, skip existing).

Pros:

- No inventory file to maintain.
- Always reflects active clients.
- Lowest operational overhead.

Cons:

- Depends on discovery endpoint data quality.
- May include short-lived clients unless guarded.

Best for:

- Dynamic lab environments where VMs come and go frequently.

### Option 2: Hybrid Discovery + Safety Gates (Recommended for Production)

Source of truth:

- Same as Option 1, plus safety checks before create/delete.

Suggested gates:

- Minimum lease recency threshold.
- Optional connectivity check to target port (`3389`) before create.
- Managed-prefix-only mutations (`AUTO_RDP_`).
- Stale deletion disabled initially, then enabled with conservative policy.

Pros:

- No manual inventory maintenance.
- Better protection against churn and accidental exposure.

Cons:

- More config complexity than pure discovery.

Best for:

- Production-like training operations where stability matters.

### Option 3: Static Inventory as Source of Truth

Source of truth:

- Maintained VM inventory file.

Pros:

- Very explicit control.
- Easy to review in change control.

Cons:

- Manual maintenance burden.
- Drift risk if inventory is not updated.

Best for:

- Highly static environments or strict change governance.

### Option 4: UPnP/NAT-PMP Dynamic Port Mapping

Source of truth:

- Client-driven dynamic requests.

Pros:

- Minimal administrative effort for clients.

Cons:

- Reduced control and auditability.
- Security posture is weaker unless tightly constrained.
- Not aligned with explicit, deterministic rule management.

Best for:

- Convenience-focused networks, not this training automation baseline.

### Decision for This Repository

- Primary recommendation: **Option 2 (Hybrid Discovery + Safety Gates)**.
- Initial rollout can start with Option 1 behavior (current script baseline), then add gates.
- Keep Option 3 as fallback for exceptional cases.
- Do not use Option 4 as the default operating model.

---

## Automation Components

Primary files:

- `port-forward-sync/sync_port_forward.py`
- `port-forward-sync/config.sample.json`
- `port-forward-sync/requirements.txt`

Optional/alternate PowerShell path (not primary for rollout):

- `poc/sync-training-rdp-nat.ps1`
- `poc/training-rdp-sync.config.sample.json`

---

## Port Mapping Standard

For each VM/client IP in training subnet:

- WAN port = `wanPortBase + last_octet(IP)`
- Target port = `3389`
- Description prefix = `AUTO_RDP_`

Example with `wanPortBase = 40000`:

- `192.168.50.21` -> WAN `40021` -> `192.168.50.21:3389`

---

## Pre-Implementation Checklist

1. Confirm pfSense API package supports these endpoints in your environment:
   - `GET /api/v1/firewall/nat/port_forward`
   - `POST /api/v1/firewall/nat/port_forward`
   - `POST /api/v1/firewall/apply`
2. Confirm token with sufficient NAT + apply permissions.
3. Confirm training interface/subnet values:
   - Interface name used in discovery filter
   - `192.168.50.0/24` (or actual subnet)
4. Confirm no existing conflicting WAN ports in chosen range.
5. Keep stale cleanup disabled for first production runs:
   - `removeStaleAutoRules = false`

---

## Configuration Plan

1. Copy sample config:

```powershell
Copy-Item .\port-forward-sync\config.sample.json .\port-forward-sync\config.json
```

2. Set environment token:

```powershell
$env:PFSENSE_FW1_TOKEN = "<FW1_API_TOKEN>"
```

3. Update `config.json` values:

- `api.baseUrl`
- discovery endpoints/response paths (if API differs)
- NAT endpoints/response shape keys
- `mapping.trainingSubnetCidr`
- `mapping.wanPortBase`

---

## Safe Rollout Procedure

1. Install dependencies:

```powershell
cd .\port-forward-sync
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r .\requirements.txt
```

2. Dry-run discovery only:

```powershell
python .\sync_port_forward.py --config .\config.json --dry-run
```

3. Generate mapping only (no pfSense writes):

```powershell
python .\sync_port_forward.py --config .\config.json --generate-only
```

4. Review generated files:

- `port-forward-sync/generated/training-rdp-nat-table.csv`
- `port-forward-sync/generated/training-rdp-nat-table.md`

5. Apply sync (idempotent create + apply):

```powershell
python .\sync_port_forward.py --config .\config.json
```

6. Validate externally:

```powershell
Test-NetConnection -ComputerName <WAN_IP> -Port <EXPECTED_PORT>
```

---

## Validation Criteria

- Script exits successfully without HTTP errors.
- Expected rules appear in pfSense NAT Port Forward list.
- No duplicate rules with same description.
- RDP connectivity works on expected WAN ports.
- `firewall/apply` is executed and changes are active.

---

## Rollback Strategy

If issues occur during first rollout:

1. Disable/Remove only rules with `AUTO_RDP_` prefix.
2. Re-run with `--generate-only` to verify intended mapping.
3. Correct config mismatch (endpoints/response fields/payload keys).
4. Re-apply in small batches.

Do not enable stale deletion until at least one stable full cycle is verified.

---

## Post-Approval Implementation Scope

After this plan is approved, implementation will cover:

1. Finalize `port-forward-sync/config.json` for your pfSense API variant.
2. Execute dry-run + generate-only + apply sequence.
3. Validate selected VM ports from external side.
4. Document final endpoint/field mappings in repo knowledge docs.

---

## Notes

- This plan intentionally avoids UPnP for training VM exposure.
- API-based management keeps rules explicit, auditable, and repeatable.
- If API response fields differ, update config mapping keys, not core script logic.
