---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T07:17:20-08:00
task_list: dotfiles/wezterm
type: report
state: archived
status: result_accepted
tags: [investigation, nushell, wezterm, kde, paths, ublue]
---

# /var/home Symlink Path Resolution in WezTerm + Nushell

> **BLUF:** The Fedora Atomic installer has a known bug where the first user's
> `/etc/passwd` entry points to `/home/mjr` (symlink) instead of `/var/home/mjr`
> (real path). This creates a `$HOME` vs `realpath($HOME)` mismatch that breaks any
> tool that canonicalizes paths — including nushell's `$nu.home-dir` and initial CWD.
> The correct fix is `sudo usermod -d /var/home/mjr mjr` to align `/etc/passwd` with
> the intended ublue convention. A nushell `login.nu` workaround can serve as a
> complementary safety net.

## Context / Background

Fedora Aurora (an ublue/Kinoite-based image) uses an immutable root filesystem. User
home directories live at `/var/home/`, with a compatibility symlink `/home → /var/home`
so POSIX-conventional paths work. The expectation is that `$HOME` and `/etc/passwd`
reference the *real* path `/var/home/mjr`.

However, the Anaconda installer has a [known bug][fedora-home-bug]: the **first user**
created during installation gets `/home/mjr` (the symlink) in `/etc/passwd`, while
users created post-installation correctly get `/var/home/mjr`. This was reported to
the Fedora KDE SIG as a defect.

Current state on this system:

```
$ getent passwd mjr
mjr:x:1000:1000:mjr:/home/mjr:/bin/bash
                     ^^^^^^^^^ should be /var/home/mjr
```

The resulting mismatch — `$HOME=/home/mjr` but `realpath($HOME)=/var/home/mjr` — is
the root cause of the path display issue. Any tool that canonicalizes paths will
produce values that don't match `$HOME`, breaking tilde substitution, prompt display,
and path comparisons.

## Key Findings

### The Fedora Atomic convention

On ublue / Fedora Atomic systems, the intended convention is:

- `/etc/passwd` home field: `/var/home/username` (the real path)
- `/home` symlink exists for compatibility, but is not the canonical reference
- Post-install `useradd` correctly uses `/var/home/`
- The installer bug only affects the first user (uid 1000)

This is consistent with the [Fedora discussion on `/etc/passwd` adaptation][fedora-passwd]
where the consensus was that `realpath($HOME) != $HOME` is "not a viable situation"
and that passwd entries should reference the real path.

### Nushell's `$nu.home-dir` canonicalizes

Nushell computes `$nu.home-dir` by canonicalizing the home path from the OS user
database. On this system:

| Value | Path |
|---|---|
| `$env.HOME` | `/home/mjr` (from passwd, the symlink) |
| `$nu.home-dir` | `/var/home/mjr` (canonicalized by nushell) |

Nushell uses `$nu.home-dir` internally for tilde replacement and CWD operations. When
it doesn't match `$env.HOME`, tilde substitution silently fails. This is tracked
upstream as [nushell#15110].

### The full resolution chain (current behavior)

```
Dolphin (resolves to physical path /var/home/mjr/Documents)
  → KTerminalLauncherJob (sets process CWD)
    → WezTerm --cwd . (inherits CWD)
      → nushell (canonicalizes inherited CWD on startup)
        → $env.PWD = /var/home/mjr/Documents
          → starship prompt: sed "s|$HOME|~|" fails
            → /home/mjr ≠ /var/home/mjr → no tilde replacement
```

### Nushell startup canonicalizes, but `cd` does not

| Scenario | Result |
|---|---|
| Start nu from `/home/mjr` (symlink) | `$env.PWD = /var/home/mjr` (canonicalized) |
| `cd /home/mjr` inside nu | `$env.PWD = /home/mjr` (symlink preserved) |
| `cd ~` inside nu | `$env.PWD = /home/mjr` (symlink preserved) |

The `cd` fix landed in nushell 0.94.0 / 0.102.0, but startup CWD canonicalization
remains in 0.110.0.

### Bash is unaffected

Bash follows POSIX `pwd -L` semantics: it checks the inherited `$PWD` env var against
the actual directory inode rather than canonicalizing. So `$PWD=/home/mjr` survives
from parent process to shell.

### WezTerm itself is fine

`wezterm cli list` reports CWD as `file://aurora/home/mjr` — the symlink path.
WezTerm's `wezterm.home_dir` reads `$HOME` correctly. The issue is entirely
downstream in nushell.

## Options Analysis

### Option 1: Fix `/etc/passwd` (recommended — addresses root cause)

```sh
sudo usermod -d /var/home/mjr mjr
```

This aligns the system with the intended ublue convention. After this change:

- `$HOME=/var/home/mjr` (from passwd)
- `$nu.home-dir=/var/home/mjr` (canonicalized — now matches `$HOME`)
- `$env.PWD=/var/home/mjr` on startup (canonicalized — now matches `$HOME`)
- Tilde replacement works everywhere: `$HOME` prefix matches `$PWD` prefix
- Starship's `sed "s|$HOME|~|"` works because both sides use `/var/home/mjr`

**Pros:**
- Fixes the root cause at the system level
- Aligns with intended Fedora Atomic convention
- Fixes ALL tools, not just nushell (Dolphin, VS Code, flatpaks, etc.)
- Zero ongoing maintenance — one-time fix

**Cons:**
- Requires `sudo` (one-time)
- Paths in shell history, bookmarks, etc. may reference the old `/home/mjr`
  (but the symlink still works, so nothing breaks)
- Any hardcoded `/home/mjr` references in configs would still work via symlink

**Risk assessment:** Low. The `/home → /var/home` symlink remains, so existing
scripts and configs that reference `/home/mjr` continue to work. The change only
affects what `$HOME` expands to going forward.

### Option 2: Normalize in nushell `login.nu` (complementary safety net)

```nu
# Normalize physical /var/home → logical /home on ublue systems.
# Safety net in case $HOME and realpath($HOME) diverge.
let logical = ($env.PWD | str replace '/var/home/' '/home/')
if $logical != $env.PWD {
  cd $logical
}
```

**Pros:** Catches any remaining edge cases where physical paths leak through.
**Cons:** Shell-level workaround; doesn't fix non-shell tools. Runs on every login.

### Option 3: Fix starship prompt only (cosmetic)

Update `starship.toml`'s `[custom.dir]` to resolve `$HOME` before comparison:

```bash
_real_home=$(readlink -f "$HOME")
_dir=$(echo "$PWD" | sed "s|$_real_home|~|g" | sed "s|$HOME|~|g")
```

**Pros:** Fixes the visible symptom.
**Cons:** `$env.PWD`, history logs, and other tools still show `/var/home/...`.

### Option 4: Wait for nushell upstream fix

[nushell#15110] tracks removing canonicalization from `$nu.home-dir`. A fix would
eliminate the mismatch from nushell's side.

**Pros:** Correct long-term fix for nushell specifically.
**Cons:** Unknown timeline; doesn't fix non-nushell tools; need a workaround
regardless.

## Recommendations

1. **Apply Option 1** (`sudo usermod -d /var/home/mjr mjr`) — this is the correct
   system-level fix, aligning with the intended Fedora Atomic convention. It resolves
   the issue for all tools, not just nushell.

2. **Optionally add Option 2** as a safety net in `login.nu` — defends against any
   other path where physical paths might leak through.

3. **Skip Option 3** — if Option 1 is applied, the starship prompt will work
   correctly without modification since `$HOME` and `$PWD` will share the same
   `/var/home/mjr` prefix.

4. **Consider commenting on [nushell#15110]** — the upstream fix to
   `$nu.home-dir` canonicalization would still be valuable for the broader community,
   even after the local passwd fix.

## Post-fix verification

After applying `usermod`, log out and back in (or reboot), then verify:

```sh
echo $HOME                    # should be /var/home/mjr
getent passwd mjr | cut -d: -f6  # should be /var/home/mjr
nu -c '$nu.home-dir'          # should be /var/home/mjr
nu -c '$env.HOME'             # should be /var/home/mjr
nu -c '$env.PWD'              # should be /var/home/mjr (from home)
```

All five should now agree on `/var/home/mjr`.

## References

- [nushell#15110 — Prompt doesn't replace $HOME with tilde on Fedora Atomic][nushell#15110]
- [nushell#2175 — Support for logical paths with pwd][nushell#2175]
- [nushell#14708 — auto cd should not canonicalize symbolic path][nushell#14708]
- [Fedora Discussion — Adapting user home in /etc/passwd][fedora-passwd]
- [Fedora Discussion — The home directory (Kinoite discrepancy)][fedora-home-bug]
- [Commit 5b67577 — Dolphin CWD fix][commit]

[nushell#15110]: https://github.com/nushell/nushell/issues/15110
[nushell#2175]: https://github.com/nushell/nushell/issues/2175
[nushell#14708]: https://github.com/nushell/nushell/pull/14708
[fedora-passwd]: https://discussion.fedoraproject.org/t/adapting-user-home-in-etc-passwd/487
[fedora-home-bug]: https://discussion.fedoraproject.org/t/the-home-directory/35482
[commit]: https://github.com/mjr/dotfiles/commit/5b67577
