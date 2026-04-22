#!/bin/bash

TARGET_DIR=$"$HOME/.local/share/claude-cleanup"

echo "Installing cleanup to $TARGET_DIR..."

mkdir -p "$TARGET_DIR"

cp -r ./* "$TARGET_DIR"
rm "$TARGET_DIR/install.sh"



echo "Installation complete!"