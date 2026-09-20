#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/home-assistant-config" >&2
  exit 64
fi

config_dir=$1
case "$config_dir" in
  ""|"/"|"$HOME")
    echo "Refusing unsafe Home Assistant config directory: $config_dir" >&2
    exit 64
    ;;
esac

if [ ! -d "$config_dir" ]; then
  echo "Home Assistant config directory does not exist: $config_dir" >&2
  exit 66
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
component_target="$config_dir/custom_components/sonance_eq"
www_target="$config_dir/www"

mkdir -p "$component_target" "$www_target"
cp -R "$script_dir/custom_components/sonance_eq/." "$component_target/"
cp "$script_dir/www/sonance-home-card.js" "$www_target/sonance-home-card.js"

echo "Installed Sonance EQ component to $component_target"
echo "Installed Sonance Home card to $www_target/sonance-home-card.js"
echo "Restart Home Assistant, add the Sonance EQ integration, then register /local/sonance-home-card.js as a dashboard resource."
