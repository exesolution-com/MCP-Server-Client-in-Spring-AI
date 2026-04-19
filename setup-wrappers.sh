#!/usr/bin/env bash
# Generates Maven wrapper files for both sub-modules.
# Run this once after cloning if mvnw is missing.
set -e

for module in mcp-tool-server ai-chat-service; do
  echo "Setting up Maven wrapper for $module..."
  cd "$module"
  mvn wrapper:wrapper -Dmaven=3.9.6 -q 2>/dev/null || \
    curl -s https://raw.githubusercontent.com/takari/maven-wrapper/master/mvnw -o mvnw && \
    chmod +x mvnw
  cd ..
done
echo "Maven wrappers ready."
