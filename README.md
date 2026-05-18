# pfSense Hyper-V Automation Toolkit

Automation toolkit for managing pfSense firewall interfaces, NAT rules, DHCP, firewall rules, and RDP port-forwarding in Hyper-V lab/training environments.

**Version:** 2.0
**Last Updated:** May 18, 2026
**Status:** Production-Ready with Professional Structure

---

## 📁 Repository Structure

```
pfsense-management/
│
├── docs/                           # Documentation
│   ├── runbooks/                   # Step-by-step guides
│   │   ├── add-new-interface.md    # Primary: Setup new interfaces
│   │   ├── quick-reference.md      # Common commands
│   │   ├── setup-kubernetes-subnet.md
│   │   └── port-forwarding.md
│   │
│   ├── troubleshooting/            # Problem resolutions
│   │   ├── training-lan-firewall-apply-fix.md
│   │   ├── training-lan-internet-nat-fix.md
│   │   ├── training1-internet-connectivity-guide.md
│   │   └── [more solutions...]
│   │
│   └── knowledge-base/             # Technical concepts
│       ├── pfsense-nat-behavior.md
│       ├── port-forward-automation-plan.md
│       └── kubernetes1-subnet-setup.md
│
├── examples/                       # Usage examples
│   └── rdp-port-forward-sync/      # Port forwarding examples
│       ├── sync_port_forward.py    # Basic synchronization
│       ├── sync-safe-mode.py       # Advanced with safety gates
│       ├── config.sample.json
│       ├── config-safe-mode.sample.json
│       └── generated/              # Sample outputs
│
├── powershell/                     # PowerShell modules and scripts
│   ├── workflows/                  # Automation scripts
│   │   ├── setup-interface.ps1     # Interface setup automation
│   │   ├── setup-kubernetes1-subnet.ps1
│   │   └── sync-rdp-port-forward.ps1
│   │
│   └── diagnostics/                # Diagnostic tools
│       └── README.md
│
├── configs/                        # Configuration templates
│   ├── samples/
│   │   ├── interface-setup.sample.json
│   │   └── port-forward.sample.json
│   │
│   └── schemas/
│       └── [JSON schemas for validation]
│
├── archive/                        # Legacy and deprecated code
│   ├── legacy-setup-interfaces/    # Original API-based setup
│   ├── poc/                        # Proof of concept experiments
│   └── old-diagnostics/            # Historical troubleshooting scripts
│
├── generated/                      # Runtime outputs (git-ignored)
│   └── [runtime state files]
│
├── tests/                          # Test suite (coming soon)
│   ├── unit/
│   ├── integration/
│   └── fixtures/
│
├── README.md                       # This file
├── PROJECT-ANALYSIS.md             # Comprehensive project documentation
├── .gitignore
└── requirements.txt               # Python dependencies
```

---

## 🚀 Quick Start

### 1. Add New Network Interface

**Start here** if you need to create a new isolated network (Training LAN, Guest network, etc.)

```powershell
# Read the comprehensive playbook
Get-Content docs/runbooks/add-new-interface.md

# Run the automated setup script
.\powershell/workflows/setup-interface.ps1 `
    -InterfaceName "TRAININGLAN" `
    -SwitchName "training-vm-lan-new" `
    -NetworkSubnet "192.168.50.0/24" `
    -PfSenseIP "192.168.50.1" `
    -HostIP "192.168.50.254"
```

**What it covers:**
- ✅ Hyper-V virtual switch setup
- ✅ Host network adapter configuration
- ✅ pfSense interface configuration
- ✅ DHCP server setup
- ✅ Firewall rules and NAT
- ✅ Connectivity validation

---

### 2. Port Forward Synchronization

Use this to automatically sync RDP port forwarding rules for training VMs:

```bash
cd examples/rdp-port-forward-sync

# Basic mode
python sync_port_forward.py --config config.sample.json --dry-run

# Safe mode (with lease age and connectivity checks)
python sync-safe-mode.py --config config-safe-mode.sample.json --apply
```

---

### 3. Troubleshoot Issues

**Having connectivity problems?**

```bash
# First, check quick reference
Get-Content docs/runbooks/quick-reference.md

# Then, check similar issues
ls docs/troubleshooting/
```

---

## 📚 Documentation by Role

### For Network Operators

1. **[Add New Interface Guide](docs/runbooks/add-new-interface.md)** - Complete setup process
2. **[Quick Reference](docs/runbooks/quick-reference.md)** - Common commands and troubleshooting
3. **[Troubleshooting Guides](docs/troubleshooting/)** - Solutions to known problems

### For Network Engineers

1. **[NAT Behavior Guide](docs/knowledge-base/pfsense-nat-behavior.md)** - Deep dive into pfSense NAT
2. **[Port Forwarding Automation](docs/knowledge-base/port-forward-automation-plan.md)** - Architectural overview
3. **[PROJECT-ANALYSIS.md](PROJECT-ANALYSIS.md)** - Complete project documentation

### For Developers

1. **[Port Forward Sync Examples](examples/rdp-port-forward-sync/)** - Python automation code
2. **[Archive POC Scripts](archive/poc/)** - API exploration examples
3. **[Legacy Setup Code](archive/legacy-setup-interfaces/)** - Historical implementation reference

---

## 🎯 Common Tasks

| Task | Location | Details |
|------|----------|---------|
| Add new interface | `docs/runbooks/add-new-interface.md` | Complete 7-phase setup |
| Sync port forwards | `examples/rdp-port-forward-sync/` | Automated RDP mapping |
| Troubleshoot connectivity | `docs/troubleshooting/` | Common issues and fixes |
| Understand NAT | `docs/knowledge-base/pfsense-nat-behavior.md` | NAT configuration guide |
| Explore API | `archive/poc/` | API exploration scripts |
| Learn the project | `PROJECT-ANALYSIS.md` | Comprehensive overview

---

## 🛠️ Technologies & Tools

### PowerShell Scripts
- `powershell/workflows/setup-interface.ps1` - Interface automation
- `powershell/workflows/sync-rdp-port-forward.ps1` - Port forward runner
- Archive: POC API exploration scripts

### Python Tools
- `examples/rdp-port-forward-sync/sync_port_forward.py` - Basic port forward sync
- `examples/rdp-port-forward-sync/sync-safe-mode.py` - Enhanced with safety gates
- Archive: Legacy interface configuration

### pfSense API
- **Version:** 2.8.1-RELEASE (API v2.6.4)
- **Authentication:** Basic Auth
- **Base URL:** `http://192.168.10.1/api/v2/`
- **Key Endpoints:**
  - `/interface` - Interface management
  - `/firewall/rules` - Firewall rules
  - `/firewall/apply` - Apply pending changes (REQUIRED!)
  - `/firewall/nat/outbound` - NAT configuration
  - `/routing/gateways` - Gateway status
  - `/status/arp` - ARP discovery
  - `/services/dhcpd/leases` - DHCP leases

---

## ⚙️ Configuration

### Port Forward Synchronization
```bash
examples/rdp-port-forward-sync/
├── config.sample.json           # Basic mode configuration
└── config-safe-mode.sample.json # Safe mode with validation
```

### Interface Setup
Configuration is interactive via PowerShell script parameters.

**⚠️ Security:** Never commit real credentials. Use `.sample.json` files as templates.

---

## 📖 Knowledge Base

### Essential Reading
1. **[Add New Interface](docs/runbooks/add-new-interface.md)** - Primary workflow
2. **[NAT Behavior](docs/knowledge-base/pfsense-nat-behavior.md)** - Understanding NAT
3. **[Quick Reference](docs/runbooks/quick-reference.md)** - Troubleshooting guide

### Troubleshooting
- [Firewall Rules Not Applied](docs/troubleshooting/training-lan-firewall-apply-fix.md)
- [NAT/Internet Not Working](docs/troubleshooting/training-lan-internet-nat-fix.md)
- [Connectivity Issues](docs/troubleshooting/training1-internet-connectivity-guide.md)

### Architecture
- [Port Forward Automation Plan](docs/knowledge-base/port-forward-automation-plan.md)
- [Kubernetes Subnet Setup](docs/knowledge-base/kubernetes1-subnet-setup.md)

---

## 🔍 Quick Navigation

| Need | Location |
|------|----------|
| **Setup new interface** | `docs/runbooks/add-new-interface.md` |
| **Sync port forwards** | `examples/rdp-port-forward-sync/` |
| **Troubleshoot issues** | `docs/troubleshooting/` |
| **Learn about NAT** | `docs/knowledge-base/pfsense-nat-behavior.md` |
| **API exploration** | `archive/poc/` |
| **Legacy code** | `archive/legacy-setup-interfaces/` |
| **Old diagnostics** | `archive/old-diagnostics/` |

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

See [docs/runbooks/quick-reference.md](docs/runbooks/quick-reference.md) for complete testing procedures.

---

## 📝 Key Concepts

### 1. Implicit vs Manual NAT
- **Primary LAN (192.168.10.0/24):** Implicit NAT (automatic)
- **Additional interfaces:** Manual NAT required
- **Common mistake:** Automatic mode doesn't work for OPT interfaces

See: [docs/knowledge-base/pfsense-nat-behavior.md](docs/knowledge-base/pfsense-nat-behavior.md)

### 2. Firewall Apply Requirement
- Rules exist in config but aren't active until applied
- **REQUIRED:** Call `POST /api/v2/firewall/apply`
- Easy to forget, causes confusion

See: [docs/troubleshooting/training-lan-firewall-apply-fix.md](docs/troubleshooting/training-lan-firewall-apply-fix.md)

### 3. Port Forwarding Modes
- **Basic:** Simple discovery and rule creation
- **Safe Mode:** Lease validation + connectivity checks

See: [examples/rdp-port-forward-sync/](examples/rdp-port-forward-sync/)

---

## 🔐 Security

- **Never commit real credentials** - Use `.sample.json` files
- Change default pfSense credentials in production
- Use HTTPS in production (not self-signed)
- Enable firewall apply validation
- Audit NAT rules regularly

---

## 📅 Recent Changes

| Date | Change |
|------|--------|
| 2026-05-18 | Reorganized to professional structure (v2.0) |
| 2026-04-29 | Added comprehensive PROJECT-ANALYSIS.md |
| Earlier | Initial implementation |

---

## 📖 Full Documentation

For comprehensive project information, see:
- **[PROJECT-ANALYSIS.md](PROJECT-ANALYSIS.md)** - Complete project overview
- **[docs/runbooks/add-new-interface.md](docs/runbooks/add-new-interface.md)** - Primary setup guide
- **[docs/knowledge-base/pfsense-nat-behavior.md](docs/knowledge-base/pfsense-nat-behavior.md)** - NAT deep dive

---

**Environment:** Hyper-V + pfSense 2.8.1-RELEASE
**Status:** Production-Ready
**Platform:** Windows PowerShell 5.1+, Python 3.x
**License:** See LICENSE file
