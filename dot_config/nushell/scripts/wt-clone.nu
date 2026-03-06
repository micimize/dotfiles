# wt-clone: Fresh bare-worktree clone command
# Creates the nikitabobko convention layout that lace's classifyWorkspace() recognizes:
#   project/.bare/        (bare git database)
#   project/.git          (gitdir: ./.bare)
#   project/main/         (worktree tracking default branch)
#   project/.worktree-root
#
# One container mounts the project/ parent; all worktrees are siblings inside it.
# See: https://nikitabobko.github.io/blog/git-worktree

const RESERVED_NAMES = [".bare", ".git", ".worktree-root"]

# ── Helpers ──

# Derive repo name from a git URL (SSH or HTTPS)
def wt-repo-name [url: string] {
  # SSH: git@github.com:org/repo.git -> split on ":", take path, basename
  # HTTPS: https://github.com/org/repo.git -> basename directly
  let path_part = if ($url | str contains ":") and not ($url | str starts-with "http") {
    $url | split row ":" | last
  } else {
    $url
  }
  $path_part | path basename | str replace -r '\.git$' ''
}

# Fix worktree gitdir paths to use relative pointers (critical for container portability)
def wt-fix-paths [name: string, root: path] {
  let worktree_git = ($root | path join $name ".git")
  let bare_gitdir = ($root | path join ".bare" "worktrees" $name "gitdir")

  $"gitdir: ../.bare/worktrees/($name)\n" | save -f $worktree_git
  $"../../($name)\n" | save -f $bare_gitdir
}

# ── Main command ──

# Clone a git repo into bare-worktree layout
export def wt-clone [
  url: string           # Git remote URL (SSH or HTTPS)
  target?: path         # Target directory (default: derived from URL)
  --branch (-b): string # Branch to checkout (default: repo's default branch)
  --name (-n): string   # Worktree directory name (default: branch name)
  --shallow             # Shallow clone (--depth 1) for large repos
] {
  let target = if ($target | is-not-empty) {
    $target | path expand
  } else {
    $env.PWD | path join (wt-repo-name $url)
  }

  # Check target directory
  if ($target | path exists) {
    let contents = (ls $target | length)
    if $contents > 0 {
      error make {
        msg: $"Target directory '($target)' already exists and is not empty. Choose a different target or remove it first."
      }
    }
  }

  # Validate --name early if provided
  if ($name | is-not-empty) and $name in $RESERVED_NAMES {
    error make {
      msg: $"Worktree name '($name)' conflicts with layout structure. Use --name to choose a different name."
    }
  }

  let bare_dir = ($target | path join ".bare")

  # Bare clone
  print $"Cloning ($url)..."
  try {
    if $shallow {
      ^git clone --bare --depth 1 $url $bare_dir
    } else {
      ^git clone --bare $url $bare_dir
    }
  } catch {
    if ($target | path exists) { rm -rf $target }
    error make { msg: "Clone failed. Check the URL and your network connection." }
  }

  # Create .git file pointing to bare db
  "gitdir: ./.bare\n" | save -f ($target | path join ".git")

  # Configure fetch refspec for all branches (bare clone default is too restrictive)
  ^git -C $bare_dir config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

  # Fetch all refs
  try {
    if $shallow {
      ^git -C $bare_dir fetch origin --depth 1
    } else {
      ^git -C $bare_dir fetch origin
    }
  } catch {
    print $"(ansi yellow)Warning: fetch failed. Remote branches may be incomplete.(ansi reset)"
  }

  # Determine default branch
  let branch = if ($branch | is-not-empty) {
    $branch
  } else {
    try {
      ^git -C $bare_dir symbolic-ref HEAD
        | str trim
        | str replace "refs/heads/" ""
    } catch {
      "main"
    }
  }

  # Determine worktree name
  let wt_name = if ($name | is-not-empty) { $name } else { $branch }

  if $wt_name in $RESERVED_NAMES {
    rm -rf $target
    error make {
      msg: $"Worktree name '($wt_name)' conflicts with layout structure. Use --name to choose a different name."
    }
  }

  # Create worktree
  try {
    ^git -C $bare_dir worktree add $"../($wt_name)" $branch
  } catch {
    rm -rf $target
    error make { msg: $"Failed to create worktree '($wt_name)' for branch '($branch)'. Does the branch exist?" }
  }

  # Fix gitdir paths to relative (container portability)
  wt-fix-paths $wt_name $target

  # Create .worktree-root marker
  "# This file marks the root of a bare-worktree layout.\n# See: https://nikitabobko.github.io/blog/git-worktree\n" | save -f ($target | path join ".worktree-root")

  # Detect submodules
  let has_submodules = ($target | path join $wt_name ".gitmodules" | path exists)

  # Summary
  if $shallow {
    print $"(ansi yellow)Note: Shallow clone. Run `git fetch --unshallow` for full history.(ansi reset)"
  }

  print $"\nCreated bare-worktree layout:"
  print $"  ($target)/"
  print $"    .bare/          \(bare git database\)"
  print $"    .git            \(gitdir: ./.bare\)"
  print $"    ($wt_name)/         \(worktree: ($branch)\)"
  print $"    .worktree-root"

  if $has_submodules {
    print $"\n(ansi yellow)This repo uses submodules. Run:(ansi reset)"
    print $"  cd ($target)/($wt_name) && git submodule update --init --recursive"
  }

  let has_devcontainer = ($target | path join $wt_name ".devcontainer" | path exists)
  print $"\nNext steps:"
  print $"  cd ($target)/($wt_name)"
  if $has_devcontainer {
    print "  lace up"
  }
}
