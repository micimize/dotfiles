if [ -n "${VSCODE_SESSION}" ]; then
  for activation_file in .vscode/*activate.sh; do
    source $activation_file
  done
  # medium_prompt
fi
