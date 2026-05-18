# pfSense Management Tools

Comprehensive toolkit for managing pfSense firewall via API and automation scripts for network interface setup, port forwarding synchronization, and troubleshooting.

**Version:** 1.0  
**Last Updated:** April 29, 2026  
**pfSense Version:** 2.8.1-RELEASE (API v2.6.4)

---

## 📁 Repository Structure

```
pfsense-management/
├── README.md                       # This file
├── .state/                         # Runtime state and temporary files
│
├── setup-interfaces-playbook/      # 🎯 Primary: New interface setup
│   ├── README.md                   # Complete step-by-step guide
│   ├── setup-interface.ps1         # Automated setup script
│   └── quick-reference.md          # Command reference card
│
├── port-forward-sync/              # 🎯 Primary: Port forwarding automation
│   ├── README.md                   # Usage documentation
│   ├── sync_port_forward.py        # Python sync script
│   ├── requirements.txt            # Python dependencies
│   └── config.sample.json          # Configuration template
│
├── setup-interfaces/               # Legacy: Manual interface setup
│   ├── README.md                   # Original setup docs
│   ├── configure_training_interface_api.py
│   ├── requirements.txt
│   └── api-config.sample.json
│
├── poc/                            # Proof of concept scripts
│   ├── README.md                   # POC documentation
│   ├── pfsense-api-poc.ps1         # API exploration
│   ├── apply-rdp-chain.ps1         # RDP chain setup
│   └── templates/                  # JSON templates
│
├── issue-wins/                     # Problem resolutions documentation
│   ├── training-lan-firewall-apply-fix.md
│   └── training-lan-internet-nat-fix.md
│
├── knowledge-book/                 # Technical knowledge base
│   ├── pfsense-nat-behavior.md     # NAT concepts and best practices
│   └── [future topics]
│
├── scripts/                        # Reusable utility scripts
│   └── [utilities coming soon]
│
└── archived-diagnostics/           # Historical troubleshooting scripts
    └── README.md                   # Archive index
```

---

## 🚀 Quick Start

### New Interface Setup

**Use this to add a new network interface to pfSense (LAN, Guest, Training, etc.)**

```powershell
cd setup-interfaces-playbook

# Automated setup
.\setup-interface.ps1 -InterfaceName "TRAININGLAN" `
    -SwitchName "training-vm-lan-new" `
    -NetworkSubnet "192.168.50.0/24" `
    -PfSenseIP "192.168.50.1" `
    -HostIP "192.168.50.254"

# Or follow manual guide
Get-Content README.md
```

**What it does:**
- ✅ Creates Hyper-V virtual switch
- ✅ Configures host network adapter
- ✅ Guides through pfSense configuration (interface, DHCP, firewall, NAT)
- ✅ Tests connectivity

**Time:** ~30 minutes

---

### Port Forward Synchronization

**Use this to sync port forwarding rules from inventory files**

```bash
cd port-forward-sync

# Configure
cp config.sample.json config.json
# Edit config.json with your settings

# Run sync
python sync_port_forward.py
```

**What it does:**
- ✅ Reads VM inventory and port mapping rules
- ✅ Creates/updates pfSense port forward rules via API
- ✅ Applies changes automatically

---

## 📚 Documentation

### For New Users

1. **[Setup Interfaces Playbook](setup-interfaces-playbook/README.md)** - Start here to add new network interfaces
2. **[Quick Reference](setup-interfaces-playbook/quick-reference.md)** - Common commands and troubleshooting
3. **[NAT Behavior Guide](knowledge-book/pfsense-nat-behavior.md)** - Understanding NAT configuration

### For Troubleshooting

1. **[Issue Wins](issue-wins/)** - Documented problem resolutions
   - Training LAN connectivity fix
   - NAT configuration issues
2. **[Archived Diagnostics](archived-diagnostics/)** - Historical troubleshooting scripts

### For Development

1. **[POC Scripts](poc/)** - API exploration and proof of concepts
2. **[Port Forward Sync](port-forward-sync/)** - Python automation tool

---

## 🎯 Primary Use Cases

### 1. Add New Network Interface

**Scenario:** Need to create a new isolated network (Training LAN, Guest network, etc.)

**Solution:** `setup-interfaces-playbook/`
- Automated script + manual guide
- Covers Hyper-V, pfSense, DHCP, Firewall, NAT
- Complete testing validation

**Documentation:**
- [Setup Guide](setup-interfaces-playbook/README.md)
- [Quick Reference](setup-interfaces-playbook/quick-reference.md)

---

### 2. Sync Port Forwarding Rules

**Scenario:** Manage port forwarding for multiple VMs from inventory files

**Solution:** `port-forward-sync/`
- Python script with JSON configuration
- Bulk create/update port forward rules
- Automatic change application

**Documentation:**
- [Port Forward README](port-forward-sync/README.md)

---

### 3. Explore pfSense API

**Scenario:** Test API endpoints, prototype automation

**Solution:** `poc/`
- PowerShell API exploration scripts
- Template JSON files
- Quick prototyping environment

**Documentation:**
- [POC README](poc/README.md)

---

## 🛠️ Tools & Technologies

### PowerShell Scripts
- `setup-interfaces-playbook/setup-interface.ps1` - Interface automation
- `poc/pfsense-api-poc.ps1` - API exploration
- `poc/apply-rdp-chain.ps1` - RDP port forward chain

### Python Tools
- `port-forward-sync/sync_port_forward.py` - Port forwarding automation
- `setup-interfaces/configure_training_interface_api.py` - Legacy interface config

### pfSense API
- Version: v2.6.4
- Authentication: Basic Auth
- Base URL: `http://192.168.10.1/api/v2/`
- Key Endpoints:
  - `/interface` - Interface management
  - `/firewall/rules` - Firewall rules
  - `/firewall/apply` - Apply pending changes
  - `/firewall/nat/outbound` - NAT configuration (limited)
  - `/routing/gateways` - Gateway status

---

## ⚙️ Configuration Files

### For Port Forward Sync
```
port-forward-sync/config.json (from config.sample.json)
```

### For Legacy Interface Setup
```
setup-interfaces/api-config.json (from api-config.sample.json)
```

### For POC Testing
```
poc/training-rdp-sync.config.json (optional)
poc/training-vm-inventory.json (optional)
```

**⚠️ Never commit files with real credentials**

---

## 📖 Knowledge Base

### NAT Configuration
- [NAT Behavior Guide](knowledge-book/pfsense-nat-behavior.md)
  - Implicit vs Manual NAT
  - Common configuration mistakes
  - Troubleshooting flowcharts

### Issue Resolutions
- [Training LAN Firewall Apply Fix](issue-wins/training-lan-firewall-apply-fix.md)
- [Training LAN Internet NAT Fix](issue-wins/training-lan-internet-nat-fix.md)

### API Reference
- Repository Memory: `.state/` (if exists)
- API Capabilities: See `knowledge-book/` for API documentation

---

## 🔍 Finding What You Need

| I want to... | Go to... |
|--------------|----------|
| Add a new network interface | `setup-interfaces-playbook/` |
| Manage port forwarding rules | `port-forward-sync/` |
| Test pfSense API | `poc/` |
| Learn about NAT | `knowledge-book/pfsense-nat-behavior.md` |
| Fix connectivity issues | `issue-wins/` + `setup-interfaces-playbook/quick-reference.md` |
| See old diagnostic scripts | `archived-diagnostics/` |
| Find reusable utilities | `scripts/` (coming soon) |

---

## 🧪 Testing & Validation

### After Interface Setup
```powershell
# From Hyper-V host
Test-Connection -ComputerName 192.168.50.1 -Count 4

# From VM
ping 192.168.50.1 -n 4    # Gateway
ping 8.8.8.8 -n 4          # Internet (NAT)
ping google.com -n 2       # DNS
```

### After Port Forward Setup
```powershell
# Test from external network
Test-NetConnection -ComputerName <WAN_IP> -Port <FORWARDED_PORT>
```

---

## 🐛 Troubleshooting

### Quick Checks

1. **No connectivity to gateway**
   ```powershell
   # Check VM is on correct virtual switch
   Get-VMNetworkAdapter -VMName "VM_NAME"
   
   # Check pfSense interface is UP
   # Web UI: Interfaces → OPT1
   ```

2. **Gateway works but no internet**
   ```powershell
   # Check NAT rule exists and is correct
   # Web UI: Firewall → NAT → Outbound
   # Source should be: [Interface] subnets (NOT "Any"!)
   ```

3. **Firewall rules not working**
   ```powershell
   # Apply pending changes via API
   Invoke-RestMethod -Uri 'http://192.168.10.1/api/v2/firewall/apply' `
       -Method POST -Headers @{Authorization="Basic $b64"; "Content-Type"="application/json"} `
       -Body '{"async":false}'
   ```

### See Also
- [Quick Reference](setup-interfaces-playbook/quick-reference.md) - Troubleshooting flowchart
- [Issue Wins](issue-wins/) - Real-world problem resolutions

---

## 📝 Best Practices

1. **Always apply changes**
   - Use API: `POST /api/v2/firewall/apply`
   - Or click "Apply Changes" in web UI

2. **Test incrementally**
   - Don't configure everything then test
   - Verify each phase before moving forward

3. **Document issues**
   - Add resolutions to `issue-wins/`
   - Update knowledge base with learnings

4. **Use descriptive names**
   - Interfaces: "TRAININGLAN" not "OPT1"
   - Rules: "Allow Training-LAN to Internet"

5. **Follow the playbook**
   - `setup-interfaces-playbook/` is tested and validated
   - Don't skip NAT configuration for additional interfaces

---

## 🔐 Security Notes

- **Never commit real credentials** to repository
- Use `.sample.json` files for configuration templates
- Add real config files to `.gitignore`
- Change default pfSense credentials in production
- Use HTTPS for production API access

---

## 🤝 Contributing

### Adding New Documentation
```
knowledge-book/          # Technical concepts and patterns
issue-wins/              # Problem resolutions
```

### Adding New Scripts
```
scripts/                 # Reusable utilities
poc/                     # Proof of concepts
```

### Archiving Old Scripts
```
archived-diagnostics/    # One-off diagnostic scripts
```

---

## 📅 Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-04-29 | 1.0 | Repository reorganization and documentation |
| 2026-04-29 | 0.9 | Training LAN setup and troubleshooting |
| Earlier | 0.x | Initial POC and port-forward-sync |

---

## 📞 Quick Links

- **Primary Playbook:** [setup-interfaces-playbook/README.md](setup-interfaces-playbook/README.md)
- **Quick Commands:** [setup-interfaces-playbook/quick-reference.md](setup-interfaces-playbook/quick-reference.md)
- **NAT Guide:** [knowledge-book/pfsense-nat-behavior.md](knowledge-book/pfsense-nat-behavior.md)
- **Port Forward:** [port-forward-sync/README.md](port-forward-sync/README.md)

---

**Environment:** Hyper-V + pfSense 2.8.1-RELEASE  
**API Version:** v2.6.4  
**Platform:** Windows PowerShell 5.1+, Python 3.x
