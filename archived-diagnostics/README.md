# Archived Diagnostics - Training LAN Troubleshooting

**Archive Date:** April 29, 2026  
**Context:** Training LAN connectivity and internet access troubleshooting

---

## Purpose of This Archive

This folder contains **ad-hoc diagnostic and troubleshooting scripts** created during the Training LAN setup and problem resolution. These scripts were created for **one-time use** to diagnose and fix specific issues.

**✅ Issues were resolved successfully!**  
See documented resolutions in:
- [issue-wins/training-lan-firewall-apply-fix.md](../issue-wins/training-lan-firewall-apply-fix.md)
- [issue-wins/training-lan-internet-nat-fix.md](../issue-wins/training-lan-internet-nat-fix.md)

---

## Files in This Archive

### PowerShell Diagnostic Scripts

#### `check-training1-status.ps1`
- **Purpose:** Check status of training_1 VM
- **What it does:** Checks VM power state, network adapter, IP configuration
- **When used:** During initial connectivity troubleshooting

#### `check-vm-adapters.ps1`
- **Purpose:** List network adapters for all VMs
- **What it does:** Shows which virtual switches VMs are connected to
- **When used:** To identify VMs on wrong virtual switches

#### `check-vm-status.ps1`
- **Purpose:** General VM status check
- **What it does:** Shows power state and basic config for all VMs
- **When used:** Initial system state assessment

#### `configure-training1-network.ps1`
- **Purpose:** Configure network settings on training_1 VM
- **What it does:** Sets static IP, gateway, DNS on VM
- **When used:** Before DHCP was properly configured

#### `diagnose-and-fix-training-lan.ps1`
- **Purpose:** Comprehensive diagnostic and fix script
- **What it does:** 
  - Checks pfSense interface status
  - Verifies firewall rules
  - Tests connectivity
  - Attempts automated fixes
- **When used:** Main troubleshooting script during issue resolution

#### `fix-training-lan-switch.ps1`
- **Purpose:** Fix virtual switch connectivity
- **What it does:** Moves VMs from wrong switch to correct switch
- **When used:** To fix root cause of connectivity issue (wrong switch)

### Documentation Files

#### `MANUAL-FIX-INSTRUCTIONS.md`
- **Purpose:** Manual steps to fix Training LAN issues
- **What it contains:** Step-by-step instructions for web UI fixes
- **Status:** Superseded by automated playbook

#### `TRAINING-LAN-DIAGNOSIS.md`
- **Purpose:** Diagnostic findings and troubleshooting notes
- **What it contains:** Real-time troubleshooting notes, test results
- **Status:** Consolidated into issue-wins documentation

---

## Why These Are Archived

### Temporary Nature
- Created for **one-time problem diagnosis**
- **Not reusable** for future interface setups
- **Too specific** to Training LAN troubleshooting
- Contain hardcoded values (training_1 VM, specific IPs)

### Better Alternatives Available

**For new interface setup:**
Use [setup-interfaces-playbook/](../setup-interfaces-playbook/) instead
- ✅ Generic and reusable
- ✅ Parameterized
- ✅ Complete documentation
- ✅ Tested and validated

**For troubleshooting:**
Use [setup-interfaces-playbook/quick-reference.md](../setup-interfaces-playbook/quick-reference.md)
- ✅ Troubleshooting flowcharts
- ✅ Common diagnostic commands
- ✅ Solution patterns

---

## Historical Context

### The Problem (April 29, 2026)
1. Training LAN interface created but VMs couldn't connect
2. VMs could ping gateway but not internet
3. Root causes:
   - VMs on wrong virtual switch (training-vm-lan vs training-vm-lan-new)
   - Firewall rules existed but weren't applied
   - NAT automatic mode not generating rules for OPT1
   - NAT rule configured backwards when manually created

### The Solution
Documented in issue-wins/:
- Fixed virtual switch assignments
- Applied firewall rules via API (`POST /api/v2/firewall/apply`)
- Switched to Manual NAT mode
- Created correct NAT rule (Source=TRAININGLAN subnets, Dest=Any)

### Lessons Learned
Captured in [knowledge-book/pfsense-nat-behavior.md](../knowledge-book/pfsense-nat-behavior.md):
- pfSense automatic NAT doesn't work for all interfaces
- Primary LAN has implicit NAT (works without manual rules)
- Additional interfaces need explicit NAT configuration
- NAT rule direction is critical (Source vs Destination)
- Always use API apply endpoint after changes

---

## Should You Use These Scripts?

### ❌ NO - For Production Use
These scripts are:
- Not parameterized
- Hardcoded for specific scenario
- May have assumptions that don't apply to your environment

### ✅ YES - For Reference
You can refer to these scripts to:
- See diagnostic techniques used
- Understand what checks were performed
- Learn troubleshooting approaches
- Adapt concepts for your own diagnostics

### ✅ BETTER - Use the Playbook
For any new interface setup, use:
[setup-interfaces-playbook/README.md](../setup-interfaces-playbook/README.md)
- Complete step-by-step guide
- Parameterized automation script
- Comprehensive testing procedures
- Troubleshooting built-in

---

## Related Documentation

### Issue Resolutions
- [Training LAN Firewall Apply Fix](../issue-wins/training-lan-firewall-apply-fix.md)
  - Problem: Firewall rules not applied
  - Solution: Use API apply endpoint

- [Training LAN Internet NAT Fix](../issue-wins/training-lan-internet-nat-fix.md)
  - Problem: NAT not configured correctly
  - Solution: Manual NAT mode with correct rule direction

### Knowledge Base
- [pfSense NAT Behavior](../knowledge-book/pfsense-nat-behavior.md)
  - Implicit vs Manual NAT
  - Common mistakes
  - Troubleshooting patterns

### Production Playbooks
- [Setup Interfaces Playbook](../setup-interfaces-playbook/)
  - Complete interface setup guide
  - Automated script with parameters
  - Testing and validation procedures

---

## Archive Maintenance

**These files should be retained for:**
- Historical reference
- Understanding troubleshooting methodology
- Learning from real-world problems

**These files can be deleted if:**
- Disk space is critical
- After 1 year (April 2027) if never referenced
- If repository is being minimized for distribution

**Recommendation:** Keep archived, they're small and provide valuable context

---

**Last Updated:** April 29, 2026  
**Archive Status:** Complete - issues resolved
**Future Action:** No action needed - reference only
