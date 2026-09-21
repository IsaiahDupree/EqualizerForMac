"""Constants for the Sonance EQ Home Assistant integration."""

DOMAIN = "sonance_eq"
NAME = "Sonance EQ"

CONF_BACKEND = "backend"
CONF_URL = "url"
CONF_TOKEN = "token"
CONF_HOST = "host"
CONF_PORT = "port"
CONF_ENTRY_ID = "config_entry_id"

BACKEND_HOME_ASSISTANT = "home_assistant"
BACKEND_MUSIC_ASSISTANT = "music_assistant"
BACKEND_POWERZONE = "powerzone"

DEFAULT_MUSIC_ASSISTANT_URL = "http://homeassistant.local:8095"
DEFAULT_POWERZONE_PORT = 7621

SERVICE_APPLY_PRESET = "apply_preset"
SERVICE_APPLY_POWERZONE_PRESET = "apply_powerzone_preset"
SERVICE_SEND_TO_DEVICE = "send_to_device"
SERVICE_SYNC_PRESETS = "sync_presets"

ATTR_ENTITY_ID = "entity_id"
ATTR_MEDIA_ID = "media_id"
ATTR_MEDIA_TYPE = "media_type"
ATTR_OUTPUT_ID = "output_id"
ATTR_PRESET = "preset"

MASS_DOMAIN = "mass"
MASS_UNIQUE_ID_PREFIX = "mass_"
