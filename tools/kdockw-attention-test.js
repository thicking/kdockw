// Temporary KWin test helper. This uses the writable KWin 6.6 Window API to
// request genuine demandsAttention on one inactive taskbar window. It never
// reads or logs window identity, title, or content.
var targetWindow = null;
var targetIndex = -1;
var testRunId = "__RUN_ID__";

function trace(phase, fields) {
    print("KDOCKW_ATTENTION_TRACE|run=" + testRunId + "|phase=" + phase + "|" + (fields || ""));
}

function run() {
    try {
        var clients = workspace.windowList();
        trace("script-enter", "windowCount=" + clients.length);
        for (var i = 0; i < clients.length; ++i) {
            var candidate = clients[i];
            if (!candidate || candidate.deleted || candidate.active
                    || candidate.minimized || candidate.specialWindow
                    || candidate.skipTaskbar || candidate.demandsAttention) {
                continue;
            }
            targetWindow = candidate;
            targetIndex = i;
            var selectedWindow = targetWindow;
            var before = !!selectedWindow.demandsAttention;
            trace("target-selected", "windowIndex=" + i
                  + "|active=" + !!selectedWindow.active
                  + "|minimized=" + !!selectedWindow.minimized
                  + "|before=" + before);
            selectedWindow.demandsAttentionChanged.connect(function() {
                trace("window-state-changed", "windowIndex=" + targetIndex
                      + "|demandsAttention=" + (!!selectedWindow && !!selectedWindow.demandsAttention));
            });
            selectedWindow.demandsAttention = true;
            var after = !!selectedWindow.demandsAttention;
            trace("setter-readback", "windowIndex=" + i
                  + "|before=" + before
                  + "|after=" + after
                  + "|active=" + !!selectedWindow.active);
            return;
        }
        trace("no-eligible-window", "windowCount=" + clients.length);
    } catch (error) {
        trace("script-error", "details=withheld");
    }
}

run();
