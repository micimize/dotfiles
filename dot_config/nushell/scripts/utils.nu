# Delete line from SSH known_hosts by line number
# (SSH error messages report line numbers: "Offending key in known_hosts:42")
def ssh-del [line: int] {
  let hosts = (open ~/.ssh/known_hosts | lines)
  $hosts | drop nth ($line - 1) | save -f ~/.ssh/known_hosts
  print $"Deleted line ($line) from known_hosts"
}

# Delete SSH known_hosts entry by hostname (canonical approach)
def ssh-del-host [host: string] {
  ^ssh-keygen -R $host
}

# Show current public IP
def showip [] {
  http get https://checkip.amazonaws.com | str trim
}

# Universal archive extraction
# Modern tar auto-detects compression, so all tar.* variants use `tar xf`.
# Standalone compression formats (gz, bz2, xz, zst, lz4) are handled separately.
def extract [file: path] {
  let ext = ($file | path parse | get extension)
  # tar.* compound extensions: modern tar auto-detects compression
  let is_tar = ($file =~ '\.(tar(\.(gz|bz2|xz|zst|lz4))?|tgz|tbz2|txz)$')
  if $is_tar {
    ^tar xf $file
  } else {
    match $ext {
      "gz" => { ^gunzip $file }
      "bz2" => { ^bunzip2 $file }
      "xz" => { ^unxz $file }
      "zst" => { ^unzstd $file }
      "lz4" => { ^lz4 -d $file }
      "zip" => { ^unzip $file }
      "rar" => { ^rar x $file }
      "7z" => { ^7z x $file }
      "Z" => { ^uncompress $file }
      _ => { error make { msg: $"Cannot extract '($file)': unknown extension '($ext)'" } }
    }
  }
}

# Track all remote git branches locally
def git-track-all [] {
  ^git branch -r
    | lines
    | where { |line| not ($line | str contains "->") }
    | each { |line| $line | str trim | str replace "origin/" "" }
    | each { |branch|
        ^git branch --track $branch $"origin/($branch)" err> /dev/null
        $branch
    }
  print "Now tracking all remote branches."
  print "To update, run: git fetch --all && git pull --all"
}

# Docker/Podman cleanup (single command handles containers, images, networks, build cache)
def docker-clean [] {
  ^docker system prune -f
}

# Kill tmux sessions by prefix (skip current)
def tmux-kill-sessions [prefix: string] {
  let current = if ($env.TMUX? | is-not-empty) {
    ^tmux display-message -p "#S" | str trim
  } else {
    ""
  }

  ^tmux list-sessions -F "#{session_name}"
    | lines
    | where { |s| ($s | str starts-with $prefix) and ($s != $current) }
    | each { |s|
        ^tmux kill-session -t $s
        print $"Killed session: ($s)"
    }
}

# Preview 256 colors
def colors-256 [] {
  0..255 | each { |i|
    let color = $"\u{1b}[48;5;($i)m(($i | fill -a right -w 4))\u{1b}[0m"
    if $i == 15 or ($i > 15 and (($i - 15) mod 6 == 0)) {
      $"($color)\n"
    } else {
      $color
    }
  } | str join "" | print
}

# Process search (replaces `ps -ef | grep`)
def searchjobs [pattern: string] {
  ps | where name =~ $pattern
}
