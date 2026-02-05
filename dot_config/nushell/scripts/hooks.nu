# Full history logging (mirrors bash's ~/.full_history)
$env.config.hooks.pre_execution ++= [{||
  let cmd = (commandline)
  if ($cmd | str trim | is-not-empty) {
    let entry = $"(date now | format date '%Y-%m-%d--%H-%M-%S') ($env._HOSTNAME) ($env.PWD) ($cmd)"
    $"($entry)\n" | save --append ~/.full_history
  }
}]
