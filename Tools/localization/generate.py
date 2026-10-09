#!/usr/bin/env python3
"""Emit reviewed-source language packs. Does not write to Apple or change prices."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Sources/SonanceEQ/Resources"
STABLE = ["Sonance EQ", "Sonance EQ Pro", "PRO", "Q", "dB/oct", "Apple Lossless", "© 2026 Isaiah Dupree", "%+.1f dB", "%.2f", "—"]
PERMISSION = {
    "en": "Sonance EQ captures your Mac’s audio to apply equalization. Recording starts only when you choose it and saves to your selected file. Audio stays on your Mac.",
    "pl": "Sonance EQ przechwytuje dźwięk Maca, aby zastosować korekcję. Nagrywanie rozpoczyna się tylko na Twoje żądanie i zapisuje w wybranym pliku. Dźwięk pozostaje na Macu.",
    "vi": "Sonance EQ thu âm thanh của máy Mac để chỉnh âm. Chỉ ghi âm khi bạn chọn và lưu vào tệp đã chọn. Âm thanh luôn ở trên máy Mac.",
    "cs": "Sonance EQ zachycuje zvuk Macu pro ekvalizaci. Nahrávání začne jen na váš pokyn a uloží se do vybraného souboru. Zvuk zůstává na Macu.",
    "it": "Sonance EQ acquisisce l’audio del Mac per equalizzarlo. La registrazione inizia solo quando la scegli e viene salvata nel file selezionato. L’audio resta sul Mac.",
    "pt-PT": "O Sonance EQ captura o áudio do Mac para aplicar equalização. A gravação só começa quando a escolher e é guardada no ficheiro selecionado. O áudio fica no Mac.",
    "el": "Το Sonance EQ καταγράφει τον ήχο του Mac για ισοστάθμιση. Η εγγραφή αρχίζει μόνο όταν το επιλέξετε και αποθηκεύεται στο επιλεγμένο αρχείο. Ο ήχος παραμένει στο Mac.",
    "hu": "A Sonance EQ a Mac hangját fogadja a hangszínszabályozáshoz. A felvétel csak az Ön kérésére indul, és a választott fájlba mentődik. A hang a Macen marad.",
    "zh-Hant": "Sonance EQ 擷取 Mac 音訊以套用等化。僅在您選擇錄製時開始，並儲存至您指定的檔案。音訊保留在 Mac 上。",
}


def emit(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("// Generated from Tools/localization/translations.tsv.\n" + "\n".join(
        f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};"
        for key, value in sorted(values.items())
    ) + "\n", encoding="utf-8")


def main():
    with (Path(__file__).parent / "translations.tsv").open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source, delimiter="|")
        rows = list(reader)
        locales = reader.fieldnames[1:]
    keys = [row["key"] for row in rows]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate translation key")
    for locale in ["en", *locales]:
        values = {row["key"]: row["key"] if locale == "en" else row[locale] for row in rows}
        if not all(values.values()):
            raise ValueError(f"Missing translation: {locale}")
        values.update({key: key for key in STABLE})
        emit(RESOURCES / f"{locale}.lproj/Localizable.strings", values)
        emit(RESOURCES / f"{locale}.lproj/InfoPlist.strings", {"NSAudioCaptureUsageDescription": PERMISSION[locale]})
    print(f"Generated {len(keys) + len(STABLE)} keys in {len(locales)} target language packs plus English.")


if __name__ == "__main__":
    main()
