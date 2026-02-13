# Fedora Atomic /var/home symlink workaround
#
# On ublue/Kinoite/Aurora, /home is a symlink to /var/home. The Anaconda
# installer has a bug where the first user (uid 1000) gets /home/user in
# /etc/passwd instead of /var/home/user. Post-install users get it right.
# This causes $HOME=/home/user but nushell canonicalizes $nu.home-dir and
# startup CWD to /var/home/user, breaking tilde substitution and prompts.
#
# Proper fix: `sudo usermod -d /var/home/$USER $USER` (requires logout, and
# usermod refuses while the user has active processes). Preferred long-term
# approach: bake the correct passwd entry into a custom Aurora derivative.
#
# Refs: https://github.com/nushell/nushell/issues/15110
#       https://github.com/nushell/nushell/issues/2175
#       https://discussion.fedoraproject.org/t/the-home-directory/35482
export def --env fix-cwd [] {
  let logical = ($env.PWD | str replace '/var/home/' '/home/')
  if $logical != $env.PWD { cd $logical }
}
