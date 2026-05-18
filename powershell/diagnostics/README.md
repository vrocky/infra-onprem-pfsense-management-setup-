# Utility Scripts

**Purpose:** Reusable utility scripts for pfSense management

---

## Directory Purpose

This folder contains **generic, reusable utility scripts** that can be used across different pfSense management tasks.

**Difference from other folders:**
- `poc/` - Proof of concept, experimental scripts
- `archived-diagnostics/` - One-time diagnostic scripts
- `scripts/` - **Reusable utilities** (this folder)
- `setup-interfaces-playbook/` - Complete workflow automation

---

## Future Utilities

Planned utilities to add here:

### Network Testing
- `test-connectivity.ps1` - Comprehensive connectivity tests
- `check-nat-status.ps1` - Verify NAT configuration

### API Helpers
- `pfsense-api.psm1` - PowerShell module for pfSense API
- `apply-firewall-changes.ps1` - Simple script to apply pending changes

### Monitoring
- `get-firewall-states.ps1` - Monitor active firewall states
- `get-interface-status.ps1` - Check all interface statuses

### Reporting
- `export-firewall-rules.ps1` - Export rules to JSON/CSV
- `export-nat-rules.ps1` - Export NAT configuration

---

## Usage Pattern

Scripts here should:
- ✅ Accept parameters (not hardcoded values)
- ✅ Have clear help documentation
- ✅ Return structured output
- ✅ Handle errors gracefully
- ✅ Be reusable in different contexts

Example:
```powershell
.\test-connectivity.ps1 -TargetIP "192.168.50.1" -TestInternet -TestDNS
```

---

## Contributing

When adding utilities here:
1. Use clear, descriptive names
2. Include comment-based help
3. Accept parameters
4. Return objects (not just Write-Host)
5. Add entry to this README

---

**Status:** Empty - utilities coming soon  
**Last Updated:** April 29, 2026
