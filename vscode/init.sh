function is_in_vscode_tmux_session {


}
if [ -n "$TMUX" ] && [[ `tmux display-message -p '#S'` == vscode* ]]; then
  tmux display-message -p '#S'
  shopt -s nullglob
  for activation_file in .vscode/*activate.sh; do
    source $activation_file
  done
  shopt -u nullglob
  # medium_prompt
fi
