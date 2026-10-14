#!/usr/bin/env bash
# Runs once when the container is created.
set -euo pipefail

# Named volumes are created owned by root; hand them to the container user.
sudo chown -R vscode:vscode \
  /home/vscode/.aws \
  /home/vscode/.config/gh \
  /home/vscode/.cache/uv \
  /home/vscode/.cache/pre-commit

pre-commit install --install-hooks

echo "Tool versions:"
python --version
uv --version
node --version
terraform version | head -n 1
aws --version
gh --version | head -n 1
pre-commit --version
make --version | head -n 1
