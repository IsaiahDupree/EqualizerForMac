from __future__ import annotations

import sys

from PySide6.QtGui import QFont, QFontDatabase

from .native import resource_root


def configure_font(application):
    root = resource_root()
    relative = "sonance/assets/InterVariable.ttf" if getattr(sys, "frozen", False) else "portable/desktop/assets/InterVariable.ttf"
    identity = QFontDatabase.addApplicationFont(str(root / relative))
    families = QFontDatabase.applicationFontFamilies(identity) if identity >= 0 else []
    if not families:
        raise RuntimeError("The bundled Sonance interface font could not be loaded.")
    application.setFont(QFont(families[0], 10))
    return families[0]
