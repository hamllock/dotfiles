#!/usr/bin/env python3
"""Trial host: runs a Wallpaper Engine *web* wallpaper on the Wayland desktop layer.
usage: webwall.py <wallpaper dir> [settings.json]
Settings = project.json defaults, overridden by settings.json (plain values, e.g. "targetfps": 30)."""
import os, sys, json, ctypes
os.environ.setdefault("QT_WAYLAND_SHELL_INTEGRATION", "layer-shell")
# Chromium: keep it lean
os.environ.setdefault("QTWEBENGINE_CHROMIUM_FLAGS",
    "--disable-features=BackForwardCache --process-per-site --disable-background-networking")
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtWebEngineQuick import QtWebEngineQuick
import shiboken6

walldir = os.path.abspath(sys.argv[1])
props = {k: {"value": v["value"]} for k, v in
         json.load(open(os.path.join(walldir, "project.json")))["general"]["properties"].items() if "value" in v}
if len(sys.argv) > 2:
    for k, v in json.load(open(sys.argv[2])).items():
        props[k] = {"value": v}

QtWebEngineQuick.initialize()
app = QGuiApplication(sys.argv)
view = QQuickView()
view.setColor("black")
view.setResizeMode(QQuickView.SizeRootObjectToView)

# put the window on the Bottom layer, anchored to all edges, ignoring panels, no keyboard focus
ls = ctypes.CDLL("libLayerShellQtInterface.so")
get = ls._ZN12LayerShellQt6Window3getEP7QWindow; get.restype = ctypes.c_void_p; get.argtypes = [ctypes.c_void_p]
w = get(shiboken6.getCppPointer(view)[0])
for sym, val in (("_ZN12LayerShellQt6Window8setLayerENS0_5LayerE", 1),          # LayerBottom
                 ("_ZN12LayerShellQt6Window10setAnchorsE6QFlagsINS0_6AnchorEE", 15),  # all edges
                 ("_ZN12LayerShellQt6Window16setExclusiveZoneEi", -1),
                 ("_ZN12LayerShellQt6Window24setKeyboardInteractivityENS0_21KeyboardInteractivityE", 0)):
    f = getattr(ls, sym); f.argtypes = [ctypes.c_void_p, ctypes.c_int]; f(w, val)

view.rootContext().setContextProperty("wallUrl", QUrl.fromLocalFile(os.path.join(walldir, "index.html")))
view.rootContext().setContextProperty("wallProps", json.dumps(props))
view.rootContext().setContextProperty("wallDebug", os.environ.get("WEBWALL_DEBUG") == "1")
view.setSource(QUrl.fromLocalFile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "webwall.qml")))
view.showFullScreen()
sys.exit(app.exec())
