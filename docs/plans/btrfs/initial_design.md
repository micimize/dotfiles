# Btrfs Backup System - Initial Design Document

## Executive Summary

This document describes the design for Phase 1 of a btrfs-based backup system: automated AWS infrastructure deployment with bidirectional sync capability. The system will serve as the foundation for a multi-device, eventually-consistent filesystem backup solution.

---

## Problem Statement

### Current Pain Points
- Manual backup processes are error-prone and inconsistent
- Setting up cloud backup infrastructure requires deep AWS/Terraform knowledge
- No easy way to share a filesystem across multiple devices with automatic sync
- Existing solutions either lack cloud backing or don't support bidirectional sync

### User Needs
1. **Automated setup**: Deploy backup infrastructure with minimal manual intervention
2. **Reliability**: Ensure backups happen consistently and can be verified
3. **Bidirectional sync**: Support both local→cloud and cloud→local transfers
4. **Troubleshooting**: Easy diagnosis when things go wrong
5. **Security**: Encrypted storage, restricted access, secure authentication

---

## Goals and Non-Goals

### Phase 1 Goals (This Design)
- ✅ Idempotent AWS infrastructure deployment via OpenTofu
- ✅ Automated setup script with validation and error handling
- ✅ Troubleshooting tools for common issues
- ✅ End-to-end testing of backup pipeline
- ✅ Comprehensive documentation
- ✅ Bidirectional sync capability (infrastructure-level)

### Non-Goals (Future Phases)
- ❌ Local btrbk configuration automation (Phase 2)
- ❌ Scheduled backups on local machines (Phase 2)
- ❌ 1Password integration (Phase 2-3)
- ❌ Multi-device conflict resolution (Phase 4)
- ❌ Eventual consistency guarantees (Phase 4)

---

## Architecture Overview

### High-Level Components

```
┌─────────────────┐                    ┌──────────────────┐
│  Local Machine  │                    │   AWS Cloud      │
│                 │                    │                  │
│  ┌───────────┐  │                    │  ┌────────────┐  │
│  │  btrfs    │  │  SSH + btrfs send  │  │  EC2       │  │
│  │  subvols  │  ├───────────────────►│  │  Instance  │  │
│  └───────────┘  │                    │  └─────┬──────┘  │
│                 │                    │        │         │
│  ┌───────────┐  │  SSH + btrfs recv  │  ┌─────▼──────┐  │
│  │  btrbk    │  │◄───────────────────┤  │  EBS Vol   │  │
│  └───────────┘  │                    │  │  (encrypted)│  │
│                 │                    │  └────────────┘  │
└─────────────────┘                    └──────────────────┘

      Phase 2                               Phase 1 (This Design)
```

### Technology Choices

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Filesystem | btrfs | Built-in snapshots, incremental send/receive, production-ready |
| Backup tool | btrbk | Purpose-built for btrfs, supports retention policies, SSH-based |
| IaC | OpenTofu | Open-source, Terraform-compatible, reproducible infrastructure |
| Cloud | AWS EC2/EBS | Reliable, encrypted storage, global availability, pay-per-use |
| Security | SSH keys + restricted commands | Standard, auditable, no additional services needed |

---

## Detailed Design

### 1. Infrastructure Layer (AWS)

#### Resources
- **EC2 Instance**: t3a.nano (minimal compute for backup target)
  - Ubuntu 22.04 LTS (stable, well-supported)
  - Persistent storage mounted at `/backup_volume`
  - Runs in user-specified region (default: us-west-1)

- **EBS Volume**: 100GB encrypted gp3
  - Encrypted at rest (AWS-managed keys)
  - Formatted as btrfs
  - Automatically mounted via /etc/fstab

- **Security Group**: SSH-only access
  - Ingress: Port 22 from 0.0.0.0/0 (user can restrict)
  - Egress: HTTP/HTTPS for package updates
  - No other ports exposed

- **SSH Key Pair**: ED25519 public key
  - User-provided public key
  - Configured for btrbk user only

#### User Configuration

**user_data Script** provisions:
1. Install btrfs-progs and btrbk
2. Format and mount EBS volume as btrfs
3. Create dedicated `btrbk` system user
4. Configure SSH with command restrictions
5. Set up btrbk-ssh wrapper script

**btrbk User**:
- Has home directory at `/home/btrbk`
- Shell: `/bin/bash` (needed for SSH command execution)
- Can only run whitelisted commands via SSH:
  - `btrfs send`, `btrfs receive`, `btrfs subvolume *`
  - `btrbk *`
- All other commands blocked by `/usr/local/bin/btrbk-ssh` wrapper

#### Security Model

```
SSH Connection
     ↓
SSH Key Auth (btrbk user)
     ↓
ForceCommand: btrbk-ssh
     ↓
Command Whitelist Check
     ↓
Execute if allowed, reject otherwise
```

**Threat Model**:
- Compromised SSH key → Limited to btrbk commands only
- Compromised EC2 instance → Data encrypted at rest, no egress except HTTPS
- Man-in-the-middle → SSH encryption, host key verification

### 2. Setup Automation Layer

#### Prerequisites Checker
**Purpose**: Validate environment before attempting deployment

**Checks**:
- OpenTofu installation and version
- AWS CLI installation and credentials
- SSH client availability
- btrfs-progs (optional, for future local setup)

**Output**: Color-coded report with installation instructions for missing tools

#### Setup Script Workflow

```
┌─────────────────────┐
│ Check Prerequisites │
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Validate tfvars     │  ← terraform.tfvars must exist with valid SSH key
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Initialize Tofu     │  ← tofu init
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Generate Plan       │  ← tofu plan -out=tfplan
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ User Confirmation   │  ← Show cost estimate, prompt for approval
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Apply Plan          │  ← tofu apply tfplan
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Wait for Ready      │  ← Poll SSH until accessible (timeout: 5 min)
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Run Smoke Tests     │  ← Validate SSH, volume, btrfs, btrbk
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Generate .env       │  ← Create aws_connection.env
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ Display Next Steps  │  ← Show connection command, docs links
└─────────────────────┘
```

**Error Handling**: Fail fast with clear error messages pointing to troubleshooting docs

**Idempotency**: Can be re-run safely; existing resources detected via Terraform state

#### Configuration Output

**aws_connection.env Format**:
```bash
# Machine-readable for scripts
BTRBK_AWS_HOST=54.123.45.67
BTRBK_AWS_USER=btrbk
BTRBK_AWS_SSH_KEY=~/.ssh/btrbk_backup
BTRBK_AWS_TARGET=ssh://btrbk@54.123.45.67/backup_volume/backups/
BTRBK_AWS_PATH=/backup_volume/backups
BTRBK_AWS_INSTANCE_ID=i-0123456789abcdef0
BTRBK_AWS_VOLUME_ID=vol-0123456789abcdef0
BTRBK_AWS_REGION=us-west-1
```

**Purpose**: Used by local setup script (Phase 2) and troubleshooting tools

### 3. Troubleshooting Layer

#### Design Philosophy
- **Subcommand structure**: `./troubleshoot.sh <check-type>`
- **Specific diagnostics**: Each check focused on one category
- **Actionable output**: Not just "failed" but "failed because X, try Y"

#### Check Types

**check-ssh**: SSH connectivity and authentication
- Tests: Basic connection, user identity, command restrictions, allowed commands
- Output: Pass/fail for each test + remediation steps
- Common issues: Key permissions, security group rules, instance stopped

**check-volume**: Backup volume status
- Tests: Mount point, filesystem type, disk space, btrfs health
- Output: Disk usage with warnings at >90%, backup directory status
- Common issues: Volume not attached, filesystem not formatted, out of space

**check-aws**: AWS resource health
- Tests: EC2 state, EBS state, volume attachment
- Output: Resource states via AWS CLI
- Common issues: Instance stopped, volume detached, region mismatch

**check-logs**: Remote system logs
- Fetches: cloud-init output (user_data script), btrbk logs (if any)
- Output: Last N lines of relevant logs
- Common issues: user_data failures, package installation errors

**check-all**: Runs all checks in sequence

#### Integration with Setup
- Setup script calls smoke tests after deployment
- Troubleshooting script can be run independently
- Both use same configuration source (aws_connection.env)

### 4. Testing Layer

#### Test Strategy

**Unit Level** (per-task):
- Terraform validation: `tofu validate`
- Script syntax: `shellcheck`
- Config files: Parsing and validation

**Integration Level** (per-component):
- Prerequisites script with missing/present tools
- Setup script with valid/invalid configs
- Troubleshooting checks with deployed infrastructure

**End-to-End Level** (full pipeline):
- Create test btrfs subvolume
- Take snapshot
- Send to AWS
- Retrieve from AWS
- Verify data integrity
- Clean up all artifacts

#### Test Script Design

```
Create Test Subvolume with Data
     ↓
Snapshot Locally (btrfs snapshot)
     ↓
Send to AWS (btrfs send | ssh | btrfs receive)
     ↓
Retrieve from AWS (ssh | btrfs send | btrfs receive)
     ↓
Verify Data Matches Original
     ↓
Clean Up (local + remote subvolumes)
```

**Requirements**:
- Local system must have btrfs filesystem
- btrbk must be installed locally
- AWS infrastructure must be deployed
- SSH access must work

**Output**: Test summary with pass/fail counts

### 5. Documentation Layer

#### Structure

```
btrfs/
├── README.md                       ← User-facing: concepts, quick start, usage
├── docs/
│   ├── TROUBLESHOOTING.md         ← Issue catalog with solutions
│   ├── 1PASSWORD_INTEGRATION.md   ← Future enhancement proposal
│   ├── LOCAL_SETUP_PLAN.md        ← Phase 2 design
│   └── plans/
│       └── btrfs/
│           ├── initial_design.md          ← This document
│           └── initial_implementation_plan.md  ← Task breakdown
```

#### Content Strategy

**README**:
- Architecture overview (why btrfs/btrbk/AWS)
- Prerequisites and installation
- Quick start (5-minute setup)
- Usage examples
- Roadmap and status

**TROUBLESHOOTING**:
- Common errors organized by symptom
- Diagnostic commands
- Step-by-step solutions
- When to file a bug report

**Design docs**:
- High-level architecture and rationale
- Not "how to use" but "why it works this way"

**Implementation plans**:
- Bite-sized tasks with code samples
- Testing instructions per task
- Assumes skilled developer, zero domain knowledge

---

## Data Flow

### Backup Flow (Local → AWS)

```
1. User data changes on local machine
      ↓
2. btrbk creates snapshot (copy-on-write, instant)
      ↓
3. btrbk determines parent snapshot (for incremental)
      ↓
4. btrfs send generates binary stream (only changed blocks)
      ↓
5. Stream sent over SSH to AWS
      ↓
6. btrfs receive on AWS reconstructs snapshot
      ↓
7. Snapshot stored on encrypted EBS volume
```

**Incremental Efficiency**:
- First backup: Full snapshot (~GB)
- Subsequent backups: Only changes (~MB)
- btrfs tracks extent sharing automatically

### Restore Flow (AWS → Local)

```
1. User requests restore (Phase 2 feature)
      ↓
2. btrbk lists available snapshots on AWS
      ↓
3. User selects snapshot by timestamp
      ↓
4. btrfs send on AWS generates stream
      ↓
5. Stream sent over SSH to local machine
      ↓
6. btrfs receive reconstructs snapshot locally
      ↓
7. User can mount snapshot read-only or copy files out
```

**Bidirectional Capability**:
- Same mechanism works in both directions
- No special "restore mode" needed
- AWS can act as snapshot source or sink

---

## Configuration Management

### Terraform Variables

**Required**:
- `ssh_public_key`: User's public SSH key (string)

**Optional with Defaults**:
- `aws_region`: AWS region (default: "us-west-1")
- `key_pair_name`: SSH key pair name (default: "btrbk-backup-key")
- `ebs_volume_size`: Volume size in GiB (default: 100)

**Not Configurable** (hardcoded for simplicity):
- Instance type: t3a.nano
- OS: Ubuntu 22.04 LTS
- Security group rules
- btrbk user configuration

**Rationale**: Start simple, add variables as needed. Users can edit .tf directly for advanced customization.

### State Management

**Terraform State**:
- Stored locally in `btrfs/terraform.tfstate`
- Committed to git (acceptable for single-user setup)
- Contains: Resource IDs, IP addresses, configuration

**Trade-offs**:
- ✅ Simple: No S3 bucket, no locking needed
- ✅ Portable: Clone repo, run setup
- ❌ Not safe for teams: Concurrent applies will conflict
- ❌ Secrets in state: Public IP, instance IDs (non-sensitive)

**Future**: Document migration to remote state for multi-user scenarios

---

## Security Considerations

### Implemented

1. **Encrypted Storage**: EBS volume encrypted at rest (AWS-managed keys)
2. **SSH Key Auth**: No passwords, public-key only
3. **Command Restrictions**: btrbk user limited to specific commands
4. **No Sudo Access**: btrbk user is non-privileged (sudo needed via root)
5. **Minimal Attack Surface**: Only SSH port exposed, no web services

### Deferred (Future Phases)

1. **Client-side Encryption**: Encrypt before sending to AWS (Phase 3)
2. **Key Rotation**: Automated SSH key rotation (Phase 3)
3. **IP Whitelisting**: Restrict SSH to known IPs (user can do manually)
4. **MFA**: Require 2FA for backup operations (Phase 3 with 1Password)
5. **Audit Logging**: Track all backup operations (Phase 3)

### Known Limitations

1. **SSH Command Bypass**: If btrbk-ssh has bugs, restricted commands could be bypassed
   - Mitigation: Code review, testing, regular updates

2. **AWS Account Compromise**: Attacker with AWS credentials can access instance
   - Mitigation: Use IAM best practices, enable CloudTrail

3. **SSH Key Theft**: Stolen private key grants access to backups
   - Mitigation: Phase 2 moves keys to 1Password with biometric unlock

4. **Man-in-the-Middle**: First connection vulnerable to MITM (no host key pinning)
   - Mitigation: Document host key verification procedure

---

## Performance Considerations

### Expected Performance

**Initial Backup** (100GB data):
- Snapshot creation: Instant (COW)
- Transfer time: ~15-30 minutes (depends on upload speed)
- Network bottleneck: Typically 50-100 Mbps upload

**Incremental Backup** (1GB changes):
- Snapshot creation: Instant
- Transfer time: ~1-2 minutes
- Only changed blocks transferred

**Restore**:
- Similar to backup (download vs. upload speeds)
- AWS egress bandwidth typically higher than home upload

### Optimization Opportunities (Future)

1. **Compression**: Enable btrfs compression (zstd) for smaller transfers
2. **Parallel Transfers**: Multiple subvolumes in parallel
3. **Bandwidth Limiting**: Don't saturate connection during backups
4. **Scheduling**: Run backups during off-peak hours
5. **Regional Replication**: Multi-region backups for disaster recovery

---

## Cost Analysis

### Monthly Cost Estimate (us-west-1)

| Resource | Unit Cost | Quantity | Monthly Cost |
|----------|-----------|----------|--------------|
| EC2 t3a.nano | $0.0047/hour | 730 hours | $3.43 |
| EBS gp3 100GB | $0.08/GB-month | 100 GB | $8.00 |
| Data Transfer Out | $0.09/GB | ~10 GB | $0.90 |
| **Total** | | | **~$12.33** |

**Assumptions**:
- Instance runs 24/7 (can stop when not backing up to save ~$3)
- 10GB/month data transfer out (restores)
- Single region
- No snapshots (btrfs snapshots, not EBS snapshots)

**Scaling**:
- Each 100GB storage: +$8/month
- Larger instance: t3a.small +$9/month (if needed)
- Multi-region replication: Double the cost

---

## Success Metrics

### Phase 1 Complete When:

- [ ] User can deploy AWS infrastructure with one command
- [ ] Setup completes in <10 minutes (including AWS provisioning)
- [ ] Smoke tests pass automatically after setup
- [ ] Troubleshooting script diagnoses common issues
- [ ] End-to-end test validates backup/restore pipeline
- [ ] Documentation enables zero-context engineer to succeed
- [ ] No manual AWS console access required

### Quality Metrics:

- [ ] All scripts pass shellcheck
- [ ] Terraform config passes `tofu validate` and `tofu fmt -check`
- [ ] Zero credentials in version control
- [ ] Error messages include remediation steps
- [ ] Each task is one atomic commit

---

## Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| AWS region unavailable | Low | High | Document multi-region setup |
| EBS volume failure | Low | High | Regular backups to multiple targets |
| SSH key lost | Medium | High | Phase 2 adds 1Password backup |
| user_data script fails | Medium | Medium | Extensive testing, detailed logs |
| btrbk bug loses data | Low | Critical | Test thoroughly, use stable versions |

### User Experience Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| User doesn't understand btrfs | High | Medium | Comprehensive docs, examples |
| Setup script fails cryptically | Medium | High | Detailed error messages, troubleshooting |
| User forgets to run backups | High | Medium | Phase 2 adds automation |
| Cost unexpectedly high | Low | Medium | Clear cost estimates in setup |

### Project Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Scope creep into Phase 2 | Medium | Medium | Strict task boundaries, defer features |
| Over-engineering | Medium | Low | YAGNI principle, start simple |
| Under-documentation | Low | High | Docs are explicit tasks in plan |
| Abandonment before Phase 2 | Medium | High | Phase 1 is useful standalone |

---

## Alternatives Considered

### Alternative 1: Use restic/borg instead of btrbk
**Pros**: More mature ecosystem, GUI tools, multiple backends
**Cons**: Not btrfs-native, full backup model less efficient, no bidirectional sync
**Decision**: btrbk chosen for btrfs integration and incremental efficiency

### Alternative 2: Use Terraform instead of OpenTofu
**Pros**: More widely adopted, better marketplace, more examples
**Cons**: No longer open-source (BUSL license), lock-in concerns
**Decision**: OpenTofu chosen for open-source principles, Terraform-compatible

### Alternative 3: Use S3 instead of EC2+EBS
**Pros**: Cheaper storage, no instance management, unlimited capacity
**Cons**: btrfs receive requires filesystem, not object storage; complex proxy needed
**Decision**: EC2+EBS chosen for simplicity and native btrfs support

### Alternative 4: Manual setup instead of automation
**Pros**: Simpler to build initially, more flexible
**Cons**: Error-prone, not reproducible, high barrier to entry
**Decision**: Automation chosen to minimize human intervention (design goal)

### Alternative 5: Docker container for AWS side
**Pros**: Easier to update, better isolation
**Cons**: Adds complexity, btrfs needs kernel support, container overhead
**Decision**: Native install chosen for simplicity and performance

---

## Future Phases Preview

### Phase 2: Local Configuration
- Automated btrbk setup on local machines
- Scheduled backups (systemd timers)
- Pre-sleep backup hooks
- Exclusion pattern configuration

### Phase 3: Enhanced Features
- 1Password integration for credentials
- Web dashboard for monitoring
- Email notifications
- Compression optimization

### Phase 4: Multi-Device Sync
- Device registry and metadata
- Conflict detection and resolution
- Eventual consistency guarantees
- Merge strategies

---

## Open Questions

1. **Should we support multiple cloud providers?**
   - Azure, GCP, DigitalOcean
   - Decision: Defer to Phase 3+, AWS-only for Phase 1

2. **How to handle btrfs not being on local machine?**
   - Fall back to rsync? Require btrfs?
   - Decision: Require btrfs (document in prerequisites)

3. **Should AWS instance be always-on or start/stop?**
   - Cost vs. convenience trade-off
   - Decision: Always-on for Phase 1, add start/stop in Phase 2

4. **How aggressively should retention policy prune snapshots?**
   - User-configurable vs. opinionated defaults
   - Decision: Provide sensible defaults, document customization

5. **Should we include monitoring/alerting?**
   - CloudWatch, SNS, email
   - Decision: Defer to Phase 3, keep Phase 1 simple

---

## References

- [btrfs Documentation](https://btrfs.readthedocs.io/)
- [btrbk Documentation](https://digint.ch/btrbk/)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [AWS EC2 Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-best-practices.html)
- [btrfs send/receive Guide](https://btrfs.wiki.kernel.org/index.php/Incremental_Backup)

---

## Approval & Sign-off

**Design Author**: Sculptor (AI)
**Review Date**: 2025-10-12
**Status**: Approved for Implementation

**Next Step**: Proceed with implementation plan in `initial_implementation_plan.md`
