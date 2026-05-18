# Dynamic Port Forward Sync (Python)

This tool keeps pfSense WAN RDP NAT rules in sync with active clients on `training-vm-lan`.

It is idempotent:
- Existing auto-managed rules are not recreated.
- New active clients get new rules.
- Optional stale-rule cleanup is supported.

## Mapping Logic

For each active client IP in training subnet:
- WAN port = `wanPortBase + IP suffix`
- Target = `<client_ip>:3389`

Example with base `40000`:
- `192.168.50.21` -> WAN `40021` -> `192.168.50.21:3389`

## Files

- `sync_port_forward.py`: Main sync script
- `config.sample.json`: Endpoint and mapping configuration
- `requirements.txt`: Python dependencies

## Setup

1. Create virtual environment (optional but recommended):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r .\requirements.txt
```

2. Create config:

```powershell
Copy-Item .\config.sample.json .\config.json
```

3. Edit `config.json`:
- Set `api.baseUrl`
- Confirm discovery endpoints for your pfSense API package
- Confirm NAT endpoints and payload template fields
- Set `mapping.trainingSubnetCidr`

4. Set token:

```powershell
$env:PFSENSE_FW1_TOKEN = "<FW1_API_TOKEN>"
```

## Run

Dry run (prints discovery requests only):

```powershell
python .\sync_port_forward.py --config .\config.json --dry-run
```

Generate mapping table without changing pfSense:

```powershell
python .\sync_port_forward.py --config .\config.json --generate-only
```

Apply idempotent sync:

```powershell
python .\sync_port_forward.py --config .\config.json
```

## Output

Generated in `outputDir` (default `generated`):
- `training-rdp-nat-table.csv`
- `training-rdp-nat-table.md`

## Notes

- Because pfSense API packages vary, endpoint paths and response shapes are configurable.
- If your API uses different field names, update config values (`responsePath`, `descriptionFields`, `idFields`, and payload template).
- Keep `removeStaleAutoRules` false until first successful production run.
