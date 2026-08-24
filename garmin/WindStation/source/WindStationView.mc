import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Full widget view. SELECT or tap cycles pages: one wind page per station
// (compass rose, big average, gust, temp, pressure trend, sparkline), then
// ONE tide page (TidePage — the Apple watch tide page). The two stations
// sit on the same bay, so a second tide page said the same thing with a
// slightly different threshold; only the Moutiers one survives.
class WindStationView extends WatchUi.View {

    var _station as Lang.Number = 0;
    var _tideDay as TidePage.Day or Null = null;
    var _snap as Lang.Dictionary or Null = null;
    var _error as Lang.String or Null = null;
    var _loading as Lang.Boolean = false;

    function initialize() {
        View.initialize();
        _snap = WindData.stored(_station);
    }

    function onShow() as Void {
        (Application.getApp() as WindStationApp).publishTide();
        _refresh();
    }

    function pageCount() as Lang.Number {
        return WindData.STATIONS.size() + 1;
    }

    function nextStation() as Void {
        _station = (_station + 1) % pageCount();
        if (_station < WindData.STATIONS.size()) {
            _snap = WindData.stored(_station);
            _refresh();
        } else {
            WatchUi.requestUpdate();
        }
    }

    function _refresh() as Void {
        if (_station >= WindData.STATIONS.size()) {
            WatchUi.requestUpdate();
            return;
        }
        _loading = true;
        _error = null;
        WindData.request(_station, method(:onWind), true);
        WatchUi.requestUpdate();
    }

    function onWind(code as Lang.Number, data) as Void {
        _loading = false;
        if (code == -1000) {
            _error = "Set token in\nGarmin Connect";
        } else if (code == 200) {
            var snap = WindData.parse(_station, data, true);
            if (snap != null) {
                _snap = snap;
                WindComplication.publish(_station, snap);
            } else {
                _error = "Bad response";
            }
        } else {
            _error = "Error " + code;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (_station >= WindData.STATIONS.size()) {
            if (_tideDay == null || (_tideDay as TidePage.Day).stale()) {
                _tideDay = new TidePage.Day();
            }
            TidePage.draw(dc, _tideDay, "Les Moutiers", TideConstants.THRESHOLDS[0]);
            return;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        var title = WindData.STATIONS[_station]["label"]
                  + " " + (_station + 1) + "/" + WindData.STATIONS.size();
        dc.drawText(cx, h * 9 / 100, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_snap == null) {
            var msg = _error != null ? _error : (_loading ? "Loading..." : "No data");
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, msg,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var dir = _snap["dir"];
        var dirText = WindData.cardinal(dir);
        if (dir != null) {
            dirText = dirText + " " + dir.toNumber() + "°";
        }
        dc.drawText(cx, h * 18 / 100, Graphics.FONT_XTINY, dirText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        _drawCompass(dc, w * 27 / 100, h * 38 / 100, w * 13 / 100, dir);

        // Speed block, right of the compass: big 5-min average, gust, and the
        // instant reading small below — the average is the number to act on,
        // the instant just shows what the sensor says right now.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var sx = w * 63 / 100;
        dc.drawText(sx, h * 32 / 100, Graphics.FONT_NUMBER_MEDIUM, WindData.knots(_snap["avg"]),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(sx + dc.getTextWidthInPixels(WindData.knots(_snap["avg"]), Graphics.FONT_NUMBER_MEDIUM) / 2 + 2,
                    h * 36 / 100, Graphics.FONT_XTINY, "kn",
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(sx, h * 46 / 100, Graphics.FONT_TINY, "Gust " + WindData.knots(_snap["gust"]),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (_snap["inst"] != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx, h * 53 / 100, Graphics.FONT_XTINY, "now " + WindData.knots(_snap["inst"]),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        _drawChips(dc, cx, h * 60 / 100);
        _drawSparkline(dc, w, h);

        // Footer: refresh state, error, or the measurement time.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var foot = _loading ? "..." : (_error != null ? _error : _measuredText());
        dc.drawText(cx, h * 92 / 100, Graphics.FONT_XTINY, foot,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Compass rose: ring, cardinal letters, needle pointing where the wind
    // comes FROM (meteorological convention, same as the iOS widget).
    function _drawCompass(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                          r as Lang.Number, dir) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, r);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var letters = ["N", "E", "S", "W"];
        for (var i = 0; i < 4; i++) {
            var a = i * Math.PI / 2;
            var lx = cx + (r + 9) * Math.sin(a);
            var ly = cy - (r + 9) * Math.cos(a);
            dc.drawText(lx, ly, Graphics.FONT_XTINY, letters[i],
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (dir == null) { return; }
        var a0 = dir.toFloat() * Math.PI / 180.0;
        var tip = [cx + (r - 3) * Math.sin(a0), cy - (r - 3) * Math.cos(a0)];
        var left = [cx + r * 0.45 * Math.sin(a0 + 2.6), cy - r * 0.45 * Math.cos(a0 + 2.6)];
        var right = [cx + r * 0.45 * Math.sin(a0 - 2.6), cy - r * 0.45 * Math.cos(a0 - 2.6)];
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([tip, left, [cx, cy], right]);
        dc.setPenWidth(1);
    }

    // Temperature (yellow) and pressure with 3h trend arrow (green), centered
    // as one line; stations without a pressure sensor just show temperature.
    function _drawChips(dc as Graphics.Dc, cx as Lang.Number, y as Lang.Number) as Void {
        var temp = _snap["temp"];
        var pressure = _snap["pressure"];
        var tempText = temp != null ? temp.toFloat().format("%.1f") + "°" : "";
        var pressText = pressure != null ? pressure.toFloat().format("%.0f") : "";
        var gap = pressText.equals("") ? "" : "   ";
        var totalW = dc.getTextWidthInPixels(tempText + gap + pressText, Graphics.FONT_TINY);
        var x = cx - totalW / 2;
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_TINY, tempText,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (pressText.equals("")) { return; }
        x += dc.getTextWidthInPixels(tempText + gap, Graphics.FONT_TINY);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_TINY, pressText,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += dc.getTextWidthInPixels(pressText, Graphics.FONT_TINY) + 3;
        _drawTrendArrow(dc, x, y, _snap["ptrend"], pressure);
    }

    // Small triangle: up when pressure rose vs 3h ago, down when it fell,
    // dash when steady (within 0.5 hPa).
    function _drawTrendArrow(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
                             was, now) as Void {
        if (was == null || now == null) { return; }
        var delta = now.toFloat() - was.toFloat();
        var s = 5;
        if (delta > 0.5) {
            dc.fillPolygon([[x, y + s], [x + 2 * s, y + s], [x + s, y - s]]);
        } else if (delta < -0.5) {
            dc.fillPolygon([[x, y - s], [x + 2 * s, y - s], [x + s, y + s]]);
        } else {
            dc.fillRectangle(x, y - 1, 2 * s, 3);
        }
    }

    // 1h wind history, min-max scaled, light blue — the iOS widget's chart.
    function _drawSparkline(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number) as Void {
        var series = _snap["series"];
        if (!(series instanceof Lang.Array) || series.size() < 2) { return; }
        var x0 = w * 16 / 100;
        var x1 = w * 84 / 100;
        var y0 = h * 68 / 100;
        var y1 = h * 86 / 100;
        var lo = series[0] as Lang.Float;
        var hi = lo;
        for (var i = 1; i < series.size(); i++) {
            var v = series[i] as Lang.Float;
            if (v < lo) { lo = v; }
            if (v > hi) { hi = v; }
        }
        var span = hi - lo;
        if (span < 0.5) { span = 0.5; } // flat wind still draws a line
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var n = series.size();
        var px = x0;
        var py = y1 - ((series[0] as Lang.Float) - lo) / span * (y1 - y0);
        for (var i = 1; i < n; i++) {
            var nx = x0 + (x1 - x0) * i / (n - 1);
            var ny = y1 - ((series[i] as Lang.Float) - lo) / span * (y1 - y0);
            dc.drawLine(px, py, nx, ny);
            px = nx;
            py = ny;
        }
        dc.setPenWidth(1);
    }

    function _measuredText() as Lang.String {
        var mAt = _snap["mAt"];
        if (mAt == null) { return ""; }
        var moment = new Time.Moment((mAt.toDouble() / 1000).toNumber());
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return "at " + info.hour.format("%02d") + ":" + info.min.format("%02d");
    }
}

// SELECT / tap cycles stations.
class WindStationDelegate extends WatchUi.BehaviorDelegate {

    var _view as WindStationView;

    function initialize(view as WindStationView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Lang.Boolean {
        _view.nextStation();
        return true;
    }
}
