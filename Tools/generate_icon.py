#!/usr/bin/env python3
"""
Generate the Sonance EQ app icon via OpenAI image generation ("living off the land": reuses an
OpenAI key already present in the local ecosystem). Writes a 1024×1024 master PNG.

Usage:
    python3 Tools/generate_icon.py [output.png] [--env /path/to/.env]

The key is read from the env file (default: MediaPoster/Backend/.env) or the OPENAI_API_KEY
environment variable. It is never printed.
"""
import base64
import json
import os
import sys
import urllib.request

PROMPT = (
    "A macOS app icon for a premium system-wide audio equalizer app called 'Sonance EQ'. "
    "Rounded-square icon (squircle) with a rich deep gradient background from indigo to violet to "
    "midnight blue. Centered, a clean glowing graphic-equalizer motif: a smooth rising-and-falling "
    "EQ response curve over softly lit vertical equalizer bars, in luminous cyan and magenta accents. "
    "Modern, minimal, high-end, Apple design-language, subtle depth and soft inner glow, crisp. "
    "No text, no letters, no words. Studio product render."
)

DEFAULT_ENV = os.path.expanduser("~/Documents/Software/MediaPoster/Backend/.env")


def load_key(env_path):
    if os.environ.get("OPENAI_API_KEY"):
        return os.environ["OPENAI_API_KEY"]
    if os.path.isfile(env_path):
        for line in open(env_path):
            line = line.strip()
            if line.startswith("OPENAI_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit(f"No OPENAI_API_KEY in env or {env_path}")


def generate(key, model):
    body = {"model": model, "prompt": PROMPT, "size": "1024x1024", "n": 1}
    if model == "gpt-image-1":
        body["quality"] = "high"
    else:  # dall-e-3
        body["response_format"] = "b64_json"
        body["quality"] = "hd"
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.load(resp)
    return base64.b64decode(data["data"][0]["b64_json"])


def main():
    out = "icon_master.png"
    env_path = DEFAULT_ENV
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--env":
            env_path = args[i + 1]; i += 2
        else:
            out = args[i]; i += 1

    key = load_key(env_path)
    for model in ("gpt-image-1", "dall-e-3"):
        try:
            print(f"Generating with {model}…")
            png = generate(key, model)
            with open(out, "wb") as f:
                f.write(png)
            print(f"✓ wrote {out} ({len(png)//1024} KB) via {model}")
            return
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:300]
            print(f"  {model} failed ({e.code}): {msg}")
    sys.exit("All image models failed.")


if __name__ == "__main__":
    main()
