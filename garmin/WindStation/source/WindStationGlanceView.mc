import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Glance: one line per station — "MOU 14.2 g18.4 NW". Stored snapshots show
// instantly; both stations refresh in place as responses arrive.
(:glance)
class WindStationGlanceView extends WatchUi.GlanceView {

    var _snaps as Lang.Array = [null, null];
    var _errors as Lang.Array = [null, null];

    function initialize() {
        GlanceView.initialize();
        _snaps = [WindData.stored(0), WindData.stored(1)];
    }

    function onShow() as Void {
        WindData.request(0, method(:onWind0), false);
        WindData.request(1, method(:onWind1), false);
    }

    function onWind0(code as Lang.Number, data) as Void {
        _handle(0, code, data);
    }

    function onWind1(code as Lang.Number, data) as Void {
        _handle(1, code, data);
    }

    function _handle(station as Lang.Number, code as Lang.Number, data) as Void {
        if (code == 200) {
            var snap = WindData.parse(station, data, true);
            if (snap != null) { _snaps[station] = snap; }
        } else if (code == -1000) {
            _errors[station] = "set token";
        } else {
            _errors[station] = code == -104 ? "no phone" : "err " + code;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var h = dc.getHeight();
        for (var i = 0; i < 2; i++) {
            var y = h * (2 * i + 1) / 4;
            dc.drawText(0, y, Graphics.FONT_GLANCE, _line(i),
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function _line(i as Lang.Number) as Lang.String {
        var station = WindData.STATIONS[i] as Lang.Dictionary;
        var name = (station["label"] as Lang.String).substring(0, 3);
        var snap = _snaps[i];
        if (!(snap instanceof Lang.Dictionary)) {
            return name + " " + (_errors[i] != null ? _errors[i] : "...");
        }
        return name + " " + WindData.knots(snap["avg"])
             + " g" + WindData.knots(snap["gust"])
             + " " + WindData.cardinal(snap["dir"]);
    }
}
