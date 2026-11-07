from __future__ import annotations

import sqlite3
from pathlib import Path

from PySide6.QtCore import QTimer, Qt
from PySide6.QtGui import QAction, QColor, QFont, QIcon, QKeySequence, QPainter, QPixmap
from PySide6.QtWidgets import (QAbstractItemView, QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog,
                              QFormLayout, QFrame, QHBoxLayout, QHeaderView, QInputDialog, QLabel,
                              QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QPushButton,
                              QSlider, QSplitter, QTableWidget, QTableWidgetItem, QTabWidget,
                              QVBoxLayout, QWidget)

import presets
from .plot import COLORS, ResponsePlot

FILTER_NAMES = {"peaking": "Peak", "lowShelf": "Low shelf", "highShelf": "High shelf",
                "lowPass": "Low pass", "highPass": "High pass", "notch": "Notch",
                "bandPass": "Band pass", "allPass": "All pass"}

STYLE = """
QMainWindow, QWidget { background:#11151e; color:#e9edf5; font-size:13px; }
QFrame#sidebar { background:#171c27; border-right:1px solid #2b3241; }
QFrame#sidebar QLabel { background:transparent; }
QFrame#card { background:#191f2b; border:1px solid #2c3444; border-radius:12px; }
QFrame#card QWidget { background:transparent; }
QLabel#brand { font-size:21px; font-weight:650; }
QLabel#eyebrow { color:#8794ab; font-size:10px; font-weight:600; }
QLabel#muted { color:#8e9bb1; }
QLabel#preview { color:#78e4c9; background:#203632; border-radius:10px; padding:5px 10px; font-size:10px; font-weight:650; }
QLineEdit, QDoubleSpinBox, QComboBox { background:#101722; border:1px solid #344055; border-radius:6px; padding:7px 9px; color:#eef2fa; selection-background-color:#3b726a; }
QLineEdit:focus, QDoubleSpinBox:focus, QComboBox:focus { border:1px solid #78e4c9; }
QLineEdit#presetName { border:none; background:transparent; font-size:25px; font-weight:600; padding:0; }
QPushButton { background:#252e3e; border:1px solid #3a465b; border-radius:6px; padding:8px 13px; font-weight:550; }
QPushButton:hover { background:#303e53; border-color:#71859e; }
QPushButton:focus { border:1px solid #78e4c9; }
QPushButton:disabled { color:#68758a; border-color:#2d3748; }
QPushButton#primary { background:#78e4c9; color:#11251f; border-color:#78e4c9; }
QPushButton#primary:hover { background:#9cf3dc; }
QPushButton:checked { background:#3c385d; border-color:#b4a6ff; color:#e5dfff; }
QPushButton#small { padding:5px 10px; }
QTabWidget::pane { border:none; }
QTabBar::tab { background:#171c27; color:#909db2; padding:10px 14px; border-bottom:2px solid transparent; }
QTabBar::tab:selected { color:#e9edf5; border-bottom-color:#78e4c9; }
QListWidget { border:none; background:transparent; outline:none; }
QListWidget::item { padding:9px 7px; border-radius:5px; }
QListWidget::item:selected { background:#2b3c4a; color:#b4f8e7; }
QTableWidget { background:transparent; border:none; gridline-color:#293344; outline:none; selection-background-color:#2c3c4b; }
QTableWidget::item { padding:6px; }
QTableWidget::item:selected { background:#2a3b4b; color:#eafbf6; }
QHeaderView::section { background:#191f2b; color:#8998ad; border:none; border-bottom:1px solid #344055; padding:7px 5px; font-size:11px; }
QCheckBox { spacing:8px; }
QCheckBox::indicator { width:16px; height:16px; border:1px solid #6b7990; border-radius:3px; background:#141b27; }
QCheckBox::indicator:checked { background:#78e4c9; border-color:#78e4c9; }
QSlider::groove:horizontal { height:5px; background:#344154; border-radius:2px; }
QSlider::sub-page:horizontal { background:#78e4c9; border-radius:2px; }
QSlider::handle:horizontal { width:14px; margin:-5px 0; background:#c6fff0; border-radius:7px; }
QStatusBar { background:#11151e; color:#8e9bb1; border-top:1px solid #273041; }
QStatusBar::item { border:none; }
QToolTip { background:#283447; color:#f0f5fc; border:1px solid #6b7f9c; padding:5px; }
QScrollBar:vertical { background:transparent; width:8px; }
QScrollBar::handle:vertical { background:#3e4b60; border-radius:4px; min-height:25px; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0; }
"""


def app_icon():
    image = QPixmap(64, 64)
    image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(QColor("#272440"))
    painter.drawRoundedRect(1, 1, 62, 62, 14, 14)
    painter.setBrush(QColor("#9bf0d7"))
    for index, height in enumerate((16, 32, 44, 25, 12)):
        painter.drawRoundedRect(13 + index * 8, 32 - height // 2, 5, height, 2, 2)
    painter.end()
    return QIcon(image)


def label(text, kind=None):
    result = QLabel(text)
    if kind:
        result.setObjectName(kind)
    return result


class EditorWindow(QMainWindow):
    def __init__(self, document):
        super().__init__()
        self.document = document
        self._updating = False
        self.setWindowTitle("Sonance EQ — Preset Editor")
        self.setWindowIcon(app_icon())
        self.resize(1320, 850)
        self.setMinimumSize(1100, 740)
        self.setStyleSheet(STYLE)
        self.save_timer = QTimer(self)
        self.save_timer.setSingleShot(True)
        self.save_timer.setInterval(350)
        self.save_timer.timeout.connect(self.save_session)
        root = QWidget()
        layout = QHBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.build_sidebar())
        layout.addWidget(self.build_editor(), 1)
        self.setCentralWidget(root)
        self.document.changed.connect(self.refresh)
        self.document.changed.connect(self.save_timer.start)
        self.document.saved.connect(self.refresh_saved)
        self.document.error.connect(self.show_error)
        self.statusBar().showMessage("Playback is not connected in this preview.")
        self.active_label = label("")
        self.statusBar().addPermanentWidget(self.active_label)
        for sequence, name, callback in (("Ctrl+O", "Import preset", self.import_dialog),
                                         ("Ctrl+Shift+S", "Export preset", self.export_dialog),
                                         ("Ctrl+S", "Save preset", self.save_dialog),
                                         ("Ctrl+B", "Bypass response", self.bypass.click)):
            action = QAction(name, self)
            action.setShortcut(QKeySequence(sequence))
            action.triggered.connect(callback)
            self.addAction(action)
        self.refresh()
        self.search_library()
        self.refresh_saved()
        if document.restore_warning:
            self.show_error(document.restore_warning)

    def button(self, text, callback, name=None, primary=False):
        button = QPushButton(text)
        if name:
            button.setObjectName(name)
        if primary:
            button.setObjectName("primary")
        button.setAccessibleName(name or text)
        button.clicked.connect(callback)
        return button

    def build_sidebar(self):
        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(246)
        column = QVBoxLayout(sidebar)
        column.setContentsMargins(17, 24, 17, 20)
        brand = QHBoxLayout()
        icon = QLabel()
        icon.setPixmap(self.windowIcon().pixmap(32, 32))
        brand.addWidget(icon)
        brand.addWidget(label("Sonance EQ", "brand"))
        brand.addStretch()
        column.addLayout(brand)
        column.addSpacing(30)
        column.addWidget(label("PRESET LIBRARY", "eyebrow"))
        self.tabs = QTabWidget()
        self.tabs.setObjectName("libraryTabs")
        headphones = QWidget()
        phones = QVBoxLayout(headphones)
        phones.setContentsMargins(0, 12, 0, 0)
        self.search = QLineEdit()
        self.search.setObjectName("headphoneSearch")
        self.search.setAccessibleName("Search headphone profiles")
        self.search.setPlaceholderText("Search headphones…")
        self.search_timer = QTimer(self)
        self.search_timer.setSingleShot(True)
        self.search_timer.setInterval(160)
        self.search.textChanged.connect(lambda *_: self.search_timer.start())
        self.search_timer.timeout.connect(self.search_library)
        phones.addWidget(self.search)
        phones.addWidget(label(f"{self.document.headphone_count:,} profiles · AutoEq", "muted"))
        self.results = QListWidget()
        self.results.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.results.setTextElideMode(Qt.TextElideMode.ElideRight)
        self.results.setObjectName("headphoneResults")
        self.results.setWordWrap(True)
        self.results.setAccessibleName("Headphone search results")
        self.results.itemDoubleClicked.connect(self.load_headphone)
        phones.addWidget(self.results, 1)
        self.search_count = label("", "muted")
        self.search_count.setWordWrap(True)
        phones.addWidget(self.search_count)
        self.load_button = self.button("Load profile", self.load_headphone, "loadHeadphone")
        phones.addWidget(self.load_button)
        self.tabs.addTab(headphones, "Headphones")
        saved = QWidget()
        saved_layout = QVBoxLayout(saved)
        saved_layout.setContentsMargins(0, 12, 0, 0)
        self.saved_list = QListWidget()
        self.saved_list.setObjectName("savedPresets")
        self.saved_list.setWordWrap(True)
        self.saved_list.itemDoubleClicked.connect(self.load_saved)
        saved_layout.addWidget(self.saved_list)
        self.saved_empty = label("Save a preset to keep a named copy here.", "muted")
        self.saved_empty.setWordWrap(True)
        saved_layout.addWidget(self.saved_empty)
        saved_layout.addWidget(self.button("Open saved preset", self.load_saved, "openSavedPreset"))
        self.tabs.addTab(saved, "Saved")
        column.addWidget(self.tabs, 1)
        column.addSpacing(14)
        footer = label("Headphone corrections from AutoEq.\nYour edits and presets stay on this device.", "muted")
        footer.setWordWrap(True)
        column.addWidget(footer)
        return sidebar

    def build_editor(self):
        panel = QWidget()
        column = QVBoxLayout(panel)
        column.setContentsMargins(26, 22, 26, 18)
        column.setSpacing(14)
        header = QHBoxLayout()
        names = QVBoxLayout()
        names.setSpacing(5)
        names.addWidget(label("EQUALIZER", "eyebrow"))
        self.name = QLineEdit()
        self.name.setObjectName("presetName")
        self.name.setAccessibleName("Preset name")
        self.name.setMaxLength(512)
        self.name.editingFinished.connect(self.rename)
        names.addWidget(self.name)
        header.addLayout(names, 1)
        header.addWidget(label("PRESET EDITOR", "preview"))
        column.addLayout(header)
        actions = QHBoxLayout()
        actions.addWidget(self.button("Reset", lambda: self.perform(self.document.reset), "resetPreset"))
        actions.addStretch()
        actions.addWidget(self.button("Import…", self.import_dialog, "importPreset"))
        actions.addWidget(self.button("Export…", self.export_dialog, "exportPreset"))
        self.save_button = self.button("Save preset…", self.save_dialog, "savePreset", primary=True)
        actions.addWidget(self.save_button)
        column.addLayout(actions)
        graph_card = QFrame()
        graph_card.setObjectName("card")
        graph_layout = QVBoxLayout(graph_card)
        graph_layout.setContentsMargins(16, 12, 16, 10)
        graph_header = QHBoxLayout()
        graph_header.addWidget(label("Frequency response"))
        graph_header.addStretch()
        graph_header.addWidget(label("Preview rate", "muted"))
        self.rate = QComboBox()
        self.rate.setObjectName("previewRate")
        self.rate.setAccessibleName("Response preview sample rate")
        for number in (44100, 48000, 96000):
            self.rate.addItem(f"{number / 1000:g} kHz", number)
        self.rate.currentIndexChanged.connect(self.change_rate)
        graph_header.addWidget(self.rate)
        graph_layout.addLayout(graph_header)
        self.plot = ResponsePlot(self.document)
        self.plot.bandSelected.connect(self.document.choose)
        self.plot.bandMoved.connect(self.move_band)
        graph_layout.addWidget(self.plot, 1)
        hint = label("Drag a point to edit a band. Select a row below for precise controls.", "muted")
        graph_layout.addWidget(hint)
        column.addWidget(graph_card, 3)
        gain_row = QHBoxLayout()
        gain_row.addWidget(label("Preamp"))
        self.preamp_slider = QSlider(Qt.Orientation.Horizontal)
        self.preamp_slider.setObjectName("preampSlider")
        self.preamp_slider.setAccessibleName("Preamp gain")
        self.preamp_slider.setRange(-600, 600)
        self.preamp_slider.valueChanged.connect(lambda value: self.perform(self.document.set_preamp, value / 10) if not self._updating else None)
        gain_row.addWidget(self.preamp_slider, 1)
        self.preamp = self.spin("preampValue", -60, 60, 3, " dB")
        self.preamp.valueChanged.connect(lambda value: self.perform(self.document.set_preamp, value) if not self._updating else None)
        self.preamp.setFixedWidth(119)
        gain_row.addWidget(self.preamp)
        gain_row.addSpacing(18)
        self.bypass = QPushButton("Bypass")
        self.bypass.setObjectName("bypassButton")
        self.bypass.setAccessibleName("Bypass equalizer response")
        self.bypass.setCheckable(True)
        self.bypass.setToolTip("Show the unprocessed response · Ctrl+B")
        self.bypass.toggled.connect(lambda enabled: self.perform(self.document.set_bypass, enabled) if not self._updating else None)
        gain_row.addWidget(self.bypass)
        column.addLayout(gain_row)
        band_card = QFrame()
        band_card.setObjectName("card")
        band_layout = QVBoxLayout(band_card)
        band_layout.setContentsMargins(16, 12, 16, 14)
        tools = QHBoxLayout()
        tools.addWidget(label("Bands"))
        tools.addStretch()
        self.add_button = self.button("+ Add band", lambda: self.perform(self.document.add_band), "addBand")
        self.remove_button = self.button("Remove", lambda: self.perform(self.document.remove_band), "removeBand")
        tools.addWidget(self.add_button)
        tools.addWidget(self.remove_button)
        band_layout.addLayout(tools)
        edit_row = QHBoxLayout()
        edit_row.setSpacing(24)
        self.table = QTableWidget(0, 5)
        self.table.setObjectName("bandTable")
        self.table.setAccessibleName("Equalizer bands")
        self.table.setHorizontalHeaderLabels(["Band", "Filter", "Frequency", "Gain", "Q"])
        self.table.verticalHeader().hide()
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setShowGrid(False)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.itemSelectionChanged.connect(self.select_row)
        self.table.itemChanged.connect(self.toggle_row)
        self.table.setMinimumHeight(172)
        edit_row.addWidget(self.table, 1)
        self.inspector = QWidget()
        form = QFormLayout(self.inspector)
        form.setContentsMargins(0, 0, 0, 0)
        form.setHorizontalSpacing(12)
        form.setVerticalSpacing(7)
        self.filter = QComboBox()
        self.filter.setObjectName("filterType")
        self.filter.setAccessibleName("Selected band filter type")
        for key in presets.FILTERS:
            self.filter.addItem(FILTER_NAMES[key], key)
        self.filter.currentIndexChanged.connect(lambda: self.edit("type", self.filter.currentData()))
        self.frequency = self.spin("bandFrequency", 1, 1e100, 3, " Hz")
        self.gain = self.spin("bandGain", -60, 60, 2, " dB")
        self.q = self.spin("bandQ", 0.0001, 100, 4)
        self.slope = QComboBox()
        self.slope.setObjectName("bandSlope")
        self.slope.setAccessibleName("Selected band cut slope")
        for number in presets.SLOPES:
            self.slope.addItem(f"{number} dB/oct", number)
        self.slope.currentIndexChanged.connect(lambda: self.edit("slopeDbPerOct", self.slope.currentData()))
        for text, widget in (("Filter", self.filter), ("Frequency", self.frequency), ("Gain", self.gain), ("Q", self.q), ("Cut slope", self.slope)):
            widget.setMinimumWidth(140)
            form.addRow(text, widget)
        self.frequency.valueChanged.connect(lambda value: self.edit("frequency", value))
        self.gain.valueChanged.connect(lambda value: self.edit("gain", value))
        self.q.valueChanged.connect(lambda value: self.edit("q", value))
        edit_row.addWidget(self.inspector)
        band_layout.addLayout(edit_row)
        column.addWidget(band_card, 2)
        self.message = label("", "muted")
        self.message.setWordWrap(True)
        self.message.setStyleSheet("color:#f2b5a0")
        self.message.hide()
        column.addWidget(self.message)
        return panel

    def spin(self, name, minimum, maximum, decimals, suffix=""):
        widget = QDoubleSpinBox()
        widget.setObjectName(name)
        widget.setAccessibleName(name)
        widget.setDecimals(decimals)
        widget.setRange(minimum, maximum)
        widget.setSuffix(suffix)
        widget.setKeyboardTracking(False)
        widget.setButtonSymbols(QDoubleSpinBox.ButtonSymbols.NoButtons)
        return widget

    def perform(self, function, *args, **kwargs):
        try:
            result = function(*args, **kwargs)
            self.message.hide()
            return result
        except (ValueError, OSError, sqlite3.Error, RuntimeError) as error:
            self.refresh()
            self.show_error(str(error))
            return None

    def show_error(self, text):
        self.message.setText(text)
        self.message.show()

    def save_session(self):
        try:
            self.document.flush()
        except OSError as error:
            self.show_error("The session could not be saved. " + str(error))

    def search_library(self):
        try:
            results = self.document.search(self.search.text())
            self.results.clear()
            for row in results:
                item = QListWidgetItem(row["model"] + "\n" + row["source"])
                item.setData(Qt.ItemDataRole.UserRole, row["id"])
                item.setToolTip(row["model"] + " · " + row["source"])
                self.results.addItem(item)
            if results:
                self.results.setCurrentRow(0)
            self.search_count.setText("100 results shown. Refine your search." if len(results) == 100 else
                                      (f"{len(results)} results" if results else "No matching headphone profiles."))
            self.load_button.setEnabled(bool(results))
        except (ValueError, OSError, sqlite3.Error) as error:
            self.show_error("The headphone library could not be searched. " + str(error))

    def load_headphone(self, *ignored):
        item = self.results.currentItem()
        if item:
            self.perform(self.document.load_headphone, item.data(Qt.ItemDataRole.UserRole))

    def refresh_saved(self):
        self.saved_list.clear()
        for name, path in self.document.saved_presets():
            item = QListWidgetItem(name)
            item.setData(Qt.ItemDataRole.UserRole, str(path))
            self.saved_list.addItem(item)
        self.saved_empty.setVisible(self.saved_list.count() == 0)

    def load_saved(self, *ignored):
        item = self.saved_list.currentItem()
        if item:
            self.perform(self.document.import_file, item.data(Qt.ItemDataRole.UserRole))

    def refresh(self):
        self._updating = True
        try:
            value = self.document.preset
            self.name.setText(value["name"])
            self.setWindowTitle(value["name"] + (" • " if self.document.modified else " — ") + "Sonance EQ")
            self.preamp.setValue(value["preampDb"])
            self.preamp_slider.setValue(round(value["preampDb"] * 10))
            self.bypass.setChecked(self.document.bypassed)
            self.bypass.setText("Bypass on" if self.document.bypassed else "Bypass")
            self.rate.setCurrentIndex(self.rate.findData(self.document.rate))
            self.table.setRowCount(len(value["bands"]))
            for index, band in enumerate(value["bands"]):
                texts = [str(index + 1), FILTER_NAMES[band["type"]], f'{band["frequency"]:g} Hz',
                         f'{band["gain"]:+.1f} dB' if band["type"] in ("peaking", "lowShelf", "highShelf") else "—", f'{band["q"]:g}']
                for column, text in enumerate(texts):
                    item = QTableWidgetItem(text)
                    if column == 0:
                        item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
                        item.setCheckState(Qt.CheckState.Checked if band["enabled"] else Qt.CheckState.Unchecked)
                        item.setForeground(QColor(COLORS[index % len(COLORS)]))
                    self.table.setItem(index, column, item)
            selected = self.document.selected
            self.inspector.setEnabled(selected >= 0)
            self.remove_button.setEnabled(selected >= 0)
            self.add_button.setEnabled(len(value["bands"]) < 32)
            if selected >= 0:
                self.table.selectRow(selected)
                band = value["bands"][selected]
                self.filter.setCurrentIndex(self.filter.findData(band["type"]))
                self.frequency.setValue(band["frequency"])
                self.gain.setValue(band["gain"])
                self.q.setValue(band["q"])
                self.slope.setCurrentIndex(self.slope.findData(band["slopeDbPerOct"]))
                self.gain.setEnabled(band["type"] in ("peaking", "lowShelf", "highShelf"))
                cut = band["type"] in ("lowPass", "highPass")
                self.slope.setEnabled(cut)
                self.q.setEnabled(not cut)
            active = sum(band["enabled"] for band in value["bands"])
            self.active_label.setText(f"{active} active bands")
            self.plot.update()
        finally:
            self._updating = False

    def edit(self, key, value):
        if not self._updating and self.document.selected >= 0:
            self.perform(self.document.edit_band, self.document.selected, **{key: value})

    def select_row(self):
        if not self._updating:
            self.document.choose(self.table.currentRow())

    def toggle_row(self, item):
        if not self._updating and item.column() == 0:
            self.perform(self.document.edit_band, item.row(), enabled=item.checkState() == Qt.CheckState.Checked)

    def move_band(self, index, frequency, gain):
        fields = {"frequency": frequency}
        if self.document.preset["bands"][index]["type"] in ("peaking", "lowShelf", "highShelf"):
            fields["gain"] = gain
        self.perform(self.document.edit_band, index, **fields)

    def change_rate(self, *ignored):
        if not self._updating:
            self.perform(self.document.install, self.document.preset, modified=self.document.modified, rate=self.rate.currentData())

    def rename(self):
        if self.name.text() != self.document.preset["name"]:
            self.perform(self.document.rename, self.name.text().strip())

    def save_dialog(self, *ignored):
        name, accepted = QInputDialog.getText(self, "Save preset", "Preset name", text=self.document.preset["name"])
        if accepted:
            self.perform(self.document.save_copy, name.strip())

    def import_dialog(self, *ignored):
        path, _ = QFileDialog.getOpenFileName(self, "Import Sonance EQ preset", "", "Sonance EQ presets (*.json)")
        if path:
            self.perform(self.document.import_file, path)

    def export_dialog(self, *ignored):
        path, _ = QFileDialog.getSaveFileName(self, "Export Sonance EQ preset", "Sonance EQ.json", "Sonance EQ presets (*.json)")
        if path:
            self.perform(self.document.export_file, path)

    def closeEvent(self, event):
        self.save_timer.stop()
        try:
            self.document.flush()
        except OSError as error:
            self.show_error("The session could not be saved. Export your preset before closing. " + str(error))
            event.ignore()
            return
        event.accept()
