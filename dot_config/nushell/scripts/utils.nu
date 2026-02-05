# Delete line from SSH known_hosts by line number
def ssh-del [line: int] {
  let hosts = (open ~/.ssh/known_hosts | lines)
  $hosts | drop nth ($line - 1) | save -f ~/.ssh/known_hosts
  print $"Deleted line ($line) from known_hosts"
}

# Show current public IP
def showip [] {
  http get https://checkip.amazonaws.com | str trim
}

# Universal archive extraction
def extract [file: path] {
  let ext = ($file | path parse | get extension)
  match $ext {
    "gz" => {
      if ($file | str ends-with ".tar.gz") or ($file | str ends-with ".tgz") {
        ^tar xzf $file
      } else {
        ^gunzip $file
      }
    }
    "bz2" => {
      if ($file | str ends-with ".tar.bz2") or ($file | str ends-with ".tbz2") {
        ^tar xjf $file
      } else {
        ^bunzip2 $file
      }
    }
    "tar" => { ^tar xf $file }
    "zip" => { ^unzip $file }
    "rar" => { ^rar x $file }
    "7z" => { ^7z x $file }
    "Z" => { ^uncompress $file }
    _ => { error make { msg: $"Cannot extract '($file)': unknown extension '($ext)'" } }
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

# Docker cleanup
def docker-clean [] {
  print "Removing stopped containers..."
  ^docker rm -v (^docker ps -a -q -f status=exited | lines) err> /dev/null
  print "Removing dangling images..."
  ^docker rmi (^docker images -f "dangling=true" -q | lines) err> /dev/null
  print "Done."
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
  } | str join ""
}

# Process search (replaces `ps -ef | grep`)
def searchjobs [pattern: string] {
  ps | where name =~ $pattern
}
