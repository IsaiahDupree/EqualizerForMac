from __future__ import annotations

import math
from PySide6.QtCore import QPoint, QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QFont, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QWidget

COLORS = ("#78e4c9", "#a798ff", "#f4bc7a", "#78bfff", "#f196be", "#c7d97a", "#f38e83", "#6ed4e5")


class ResponsePlot(QWidget):
    bandMoved = Signal(int, float, float)
    bandSelected = Signal(int)

    def __init__(self, document, parent=None):
        super().__init__(parent)
        self.document = document
        self.dragged = -1
        self.setObjectName("responsePlot")
        self.setAccessibleName("Equalizer frequency response and draggable band handles")
        self.setMinimumHeight(150)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        document.changed.connect(self.update)

    def plot_rect(self):
        return QRectF(48, 18, max(1, self.width() - 70), max(1, self.height() - 55))

    def x(self, frequency):
        rect = self.plot_rect()
        return rect.left() + math.log10(max(20, min(20000, frequency)) / 20) / 3 * rect.width()

    def y(self, gain):
        rect = self.plot_rect()
        return rect.center().y() - gain / (2 * self.extent()) * rect.height()

    def extent(self):
        values = self.document.response + [band["gain"] for band in self.document.preset["bands"]]
        peak = max((abs(value) for value in values), default=0)
        return max(12, math.ceil(peak / 6) * 6)

    def handle(self, index):
        band = self.document.preset["bands"][index]
        gain = band["gain"] if band["type"] in ("peaking", "lowShelf", "highShelf") else 0
        return QPointF(self.x(band["frequency"]), self.y(gain))

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        rect = self.plot_rect()
        font = QFont(self.font())
        font.setPointSize(9)
        painter.setFont(font)
        ticks = (20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000)
        for frequency in ticks:
            x = self.x(frequency)
            painter.setPen(QPen(QColor("#29303d"), 1))
            painter.drawLine(QPointF(x, rect.top()), QPointF(x, rect.bottom()))
            painter.setPen(QColor("#8793a7"))
            label = str(frequency) if frequency < 1000 else str(frequency // 1000) + "k"
            painter.drawText(QRectF(x - 25, rect.bottom() + 9, 50, 20), Qt.AlignmentFlag.AlignCenter, label)
        extent = self.extent()
        for gain in (-extent, -extent / 2, 0, extent / 2, extent):
            y = self.y(gain)
            painter.setPen(QPen(QColor("#465064" if gain == 0 else "#29303d"), 1))
            painter.drawLine(QPointF(rect.left(), y), QPointF(rect.right(), y))
            painter.setPen(QColor("#8793a7"))
            painter.drawText(QRectF(0, y - 9, 39, 18), Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter,
                             ("+" if gain > 0 else "") + f"{gain:g}")
        painter.save()
        painter.setClipRect(rect.adjusted(-1, -1, 1, 1))
        path = QPainterPath()
        for index, (frequency, gain) in enumerate(zip(self.document.frequencies, self.document.response)):
            point = QPointF(self.x(frequency), self.y(gain))
            path.moveTo(point) if index == 0 else path.lineTo(point)
        if not path.isEmpty():
            fill = QPainterPath(path)
            fill.lineTo(rect.right(), self.y(0))
            fill.lineTo(rect.left(), self.y(0))
            fill.closeSubpath()
            painter.fillPath(fill, QColor(120, 228, 201, 17) if not self.document.bypassed else QColor(130, 143, 166, 10))
        painter.setPen(QPen(QColor("#78e4c9" if not self.document.bypassed else "#8793a7"), 2.3))
        painter.drawPath(path)
        painter.restore()
        for index, band in enumerate(self.document.preset["bands"]):
            position = self.handle(index)
            color = QColor(COLORS[index % len(COLORS)] if band["enabled"] else "#687387")
            selected = index == self.document.selected
            if selected:
                halo = QColor(color)
                halo.setAlpha(35)
                painter.setPen(Qt.PenStyle.NoPen)
                painter.setBrush(halo)
                painter.drawEllipse(position, 16, 16)
            painter.setPen(QPen(color, 2 if selected else 1.4))
            painter.setBrush(QColor("#121824") if not band["enabled"] else color)
            painter.drawEllipse(position, 9, 9)
            painter.setPen(QColor("#111720" if band["enabled"] else "#a8b2c4"))
            painter.drawText(QRectF(position.x() - 10, position.y() - 10, 20, 20), Qt.AlignmentFlag.AlignCenter, str(index + 1))

    def mousePressEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        hits = [(math.hypot(self.handle(index).x() - event.position().x(), self.handle(index).y() - event.position().y()), index)
                for index in range(len(self.document.preset["bands"]))]
        if hits and min(hits)[0] <= 18:
            self.dragged = min(hits)[1]
            self.bandSelected.emit(self.dragged)
            self.setCursor(Qt.CursorShape.ClosedHandCursor)

    def mouseMoveEvent(self, event):
        if self.dragged < 0:
            return
        rect = self.plot_rect()
        relative = max(0, min(1, (event.position().x() - rect.left()) / rect.width()))
        frequency = 20 * 1000 ** relative
        gain = max(-60, min(60, (rect.center().y() - event.position().y()) / rect.height() * 2 * self.extent()))
        self.bandMoved.emit(self.dragged, frequency, gain)

    def mouseReleaseEvent(self, event):
        self.dragged = -1
        self.unsetCursor()
