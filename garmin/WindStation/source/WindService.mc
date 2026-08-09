import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

// Background temporal event (every 15 min): fetch both stations' light wind
// data sequentially and hand the snapshots to the app via Background.exit —
// the app persists them and refreshes the complications, so watch-face wind
// stays current without ever opening the widget.
(:background)
class WindService extends System.ServiceDelegate {

    var _snaps as Lang.Dictionary = {};

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        WindData.request(0, method(:onStation0), false);
    }

    function onStation0(code as Lang.Number, data) as Void {
        if (code == 200) {
            var snap = WindData.parse(0, data, false);
            if (snap != null) { _snaps[0] = snap; }
        }
        WindData.request(1, method(:onStation1), false);
    }

    function onStation1(code as Lang.Number, data) as Void {
        if (code == 200) {
            var snap = WindData.parse(1, data, false);
            if (snap != null) { _snaps[1] = snap; }
        }
        Background.exit(_snaps.size() > 0 ? _snaps : null);
    }
}
