if [ -n "${VSCODE_SESSION}" ]; then
  shopt -s nullglob
  for activation_file in .vscode/*activate.sh; do
    source $activation_file
  done
  shopt -u nullglob
  # medium_prompt
fi
