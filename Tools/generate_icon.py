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
    "A premium macOS app icon, Apple Big Sur design language, for a high-end system-wide audio "
    "equalizer called 'Sonance EQ'. A single rounded-square (squircle) that fills the frame, with a "
    "rich glossy gradient background flowing from deep indigo at the top through violet to vivid "
    "magenta at the bottom, with a soft inner glow and a subtle top highlight for depth. The hero "
    "element is ONE bold, luminous parametric EQ response curve — a smooth glowing bell/S-shaped line "
    "sweeping left to right in bright cyan-to-magenta, with two or three small glowing node dots sitting "
    "on the curve, and a soft neon glow beneath it. Faint, low-contrast vertical frequency bars sit "
    "quietly behind the curve for texture. Minimal, confident, three-dimensional, studio product render, "
    "crisp at small sizes, centered, clean negative space. No text, no letters, no words, no numbers."
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
