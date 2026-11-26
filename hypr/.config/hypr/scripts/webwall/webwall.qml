import QtQuick
import QtWebEngine
WebEngineView {
    id: web
    url: wallUrl
    backgroundColor: "black"
    settings.localContentCanAccessFileUrls: true
    settings.playbackRequiresUserGesture: false
    settings.showScrollBars: false
    onContextMenuRequested: (req) => req.accepted = true   // no right-click menu on the desktop
    onLoadingChanged: (req) => {
        if (req.status === WebEngineView.LoadSucceededStatus)
            web.runJavaScript("window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties(" + wallProps + ")")
    }
    onJavaScriptConsoleMessage: (level, msg) => { if (wallDebug) console.log("JS", msg) }
    onRenderProcessTerminated: (status, code) => { console.log("renderer died", status, code); reloadTimer.start() }
    Timer { id: reloadTimer; interval: 2000; onTriggered: web.reload() }
}
