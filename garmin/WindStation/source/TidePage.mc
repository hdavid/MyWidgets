import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The tide page, drawn exactly like the Apple watch tide page (which is the
// one-day tide widget): title + today's coefficients header over the day
// curve with dashed threshold line, ↑/↓ crossing times on the line, high/low
// water time+height labels and the red now-marker. All computed locally from
// TideConstants — no network, ever. One page per location; only the
// threshold differs (same water).
module TidePage {

    // One computed day, cached by the view and recomputed when the day rolls
    // or after ~20 min so the now-marker keeps moving.
    class Day {
        var start as Lang.Number;        // local midnight, epoch s
        var step as Lang.Number = 1200;
        var curve as Lang.Array;         // table-metres, 145 samples
        var extremes as Lang.Array;      // [tsec, height, isHigh]
        var coefs as Lang.Array;         // today's HW coefficients
        var computedAt as Lang.Number;

        function initialize() {
            computedAt = Time.now().value();
            start = Time.today().value();
            var ctx = TideMath.pornicCtx(start);
            var count = 86400 / step;
            curve = new [count + 1];
            for (var i = 0; i <= count; i++) {
                curve[i] = TideMath.tableFromCm(TideMath.evalCtx(ctx, start + i * step));
            }
            // Pad past midnight so an extremum near the edges still refines.
            extremes = TideMath.extremes(TideMath.PORT_PORNIC, start - 3 * 3600,
                                         start + 86400 + 3 * 3600, step);
            coefs = [];
            for (var i = 0; i < extremes.size(); i++) {
                var e = extremes[i];
                if (e[2] && e[0] >= start && e[0] < start + 86400) {
                    var c = TideMath.coefficient(e[0]);
                    if (c != null) { coefs.add(c); }
                }
            }
        }

        function stale() as Lang.Boolean {
            var now = Time.now().value();
            return now - computedAt > 1200 || Time.today().value() != start;
        }

        // Crossing instants of `threshold` inside the day, by linear
        // interpolation on the curve: array of [tsec, rising].
        function crossings(threshold as Lang.Float) as Lang.Array {
            var out = [];
            for (var i = 1; i < curve.size(); i++) {
                var a = curve[i - 1] - threshold;
                var b = curve[i] - threshold;
                if (a == 0.0 || (a < 0) == (b < 0)) { continue; }
                var f = a.abs() / (a.abs() + b.abs());
                out.add([start + (i - 1) * step + (f * step).toNumber(), b > a]);
            }
            return out;
        }
    }

    function hm(tsec as Lang.Number) as Lang.String {
        var info = Gregorian.info(new Time.Moment(tsec), Time.FORMAT_SHORT);
        return info.hour.format("%02d") + "h" + info.min.format("%02d");
    }

    // MIP-palette stand-ins for the Apple widget's colors.
    const BLUE = 0x00AAFF;
    const DARKBLUE = 0x000055;
    const GREEN = 0x00AA00;
    const ORANGE = 0xFF5500;
    const GRAY = 0xAAAAAA;

    function draw(dc as Graphics.Dc, day as Day, title as Lang.String,
                  threshold as Lang.Float) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Header: title left, "coef 48·53" right — inset on a round face.
        dc.drawText(w * 22 / 100, h * 8 / 100, Graphics.FONT_XTINY, title,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (day.coefs.size() > 0) {
            var big = false;
            var parts = "";
            for (var i = 0; i < day.coefs.size(); i++) {
                parts += (i > 0 ? "·" : "") + day.coefs[i];
                if (day.coefs[i] >= 90) { big = true; }
            }
            dc.setColor(big ? ORANGE : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 78 / 100, h * 8 / 100, Graphics.FONT_XTINY, "C " + parts,
                        Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var top = h * 22 / 100;      // room for header + HW labels
        var bottom = h * 88 / 100;   // room for LW labels
        var lo = threshold;
        var hi = threshold;
        for (var i = 0; i < day.curve.size(); i++) {
            if (day.curve[i] < lo) { lo = day.curve[i]; }
            if (day.curve[i] > hi) { hi = day.curve[i]; }
        }
        lo -= 0.3;
        hi += 0.3;

        var count = day.curve.size() - 1;

        // Fill under the curve (per pixel column, values interpolated), then
        // the curve itself.
        dc.setColor(DARKBLUE, Graphics.COLOR_TRANSPARENT);
        for (var px = 0; px < w; px++) {
            var fi = px * count / w.toFloat();
            var i0 = fi.toNumber();
            var i1 = i0 + 1 > count ? count : i0 + 1;
            var v = day.curve[i0] + (day.curve[i1] - day.curve[i0]) * (fi - i0);
            var py = bottom - (bottom - top) * (v - lo) / (hi - lo);
            dc.drawLine(px, py, px, h);
        }
        dc.setColor(BLUE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 1; i <= count; i++) {
            dc.drawLine(w * (i - 1) / count,
                        bottom - (bottom - top) * (day.curve[i - 1] - lo) / (hi - lo),
                        w * i / count,
                        bottom - (bottom - top) * (day.curve[i] - lo) / (hi - lo));
        }
        dc.setPenWidth(1);

        // Threshold: dashed line, value tag, crossing times on the line.
        var ty = bottom - (bottom - top) * (threshold - lo) / (hi - lo);
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        for (var x = 0; x < w; x += 7) {
            dc.drawLine(x, ty, x + 3, ty);
        }
        dc.drawText(w - 2, ty - 12, Graphics.FONT_XTINY,
                    threshold.format("%.1f"),
                    Graphics.TEXT_JUSTIFY_RIGHT);
        // Crossings: a small triangle (Garmin fonts have no arrow glyphs)
        // pointing the way the water is going, time text beside it.
        var crossings = day.crossings(threshold);
        for (var i = 0; i < crossings.size(); i++) {
            var c = crossings[i];
            var cx = w * (c[0] - day.start) / 86400;
            if (cx < 30 || cx > w - 34) { continue; }
            if (c[1]) {
                dc.fillPolygon([[cx - 8, ty + 9], [cx - 2, ty + 9], [cx - 5, ty + 3]]);
                dc.drawText(cx - 1, ty + 2, Graphics.FONT_XTINY, hm(c[0]),
                            Graphics.TEXT_JUSTIFY_LEFT);
            } else {
                dc.fillPolygon([[cx - 8, ty - 9], [cx - 2, ty - 9], [cx - 5, ty - 3]]);
                dc.drawText(cx - 1, ty - 17, Graphics.FONT_XTINY, hm(c[0]),
                            Graphics.TEXT_JUSTIFY_LEFT);
            }
        }

        // Extremes: time + height, above highs, below lows.
        for (var i = 0; i < day.extremes.size(); i++) {
            var e = day.extremes[i];
            if (e[0] < day.start || e[0] >= day.start + 86400) { continue; }
            var px = w * (e[0] - day.start) / 86400;
            var py = bottom - (bottom - top) * (e[1] - lo) / (hi - lo);
            // The round face narrows near top and bottom — clamp harder there.
            var m = (py < h * 35 / 100 || py > h * 72 / 100) ? 52 : 36;
            if (px < m) { px = m; }
            if (px > w - m) { px = w - m; }
            dc.setColor(e[2] ? Graphics.COLOR_WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(px, e[2] ? py - 18 : py + 3, Graphics.FONT_XTINY,
                        hm(e[0]) + " " + e[1].format("%.1f"),
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Now.
        var now = Time.now().value();
        if (now >= day.start && now < day.start + 86400) {
            var nx = w * (now - day.start) / 86400;
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(nx, top, nx, bottom);
            var idx = (now - day.start) / day.step;
            if (idx >= 0 && idx < day.curve.size()) {
                var ny = bottom - (bottom - top) * (day.curve[idx] - lo) / (hi - lo);
                dc.fillCircle(nx, ny, 3);
            }
        }
    }

    // Complication value, Apple-label style: "4.6m↗ C74".
    function complicationValue() as Lang.String {
        var now = Time.now().value();
        var height = TideMath.table(now);
        var rising = TideMath.table(now + 900) > height;
        var text = height.format("%.1f") + "m" + (rising ? "↗" : "↘");
        // The running tide's coefficient: the high we're leaving or heading to.
        var ext = TideMath.extremes(TideMath.PORT_PORNIC, now - 9 * 3600, now + 9 * 3600, 900);
        var high = null;
        var bestDt = 9 * 3600;
        for (var i = 0; i < ext.size(); i++) {
            if (!ext[i][2]) { continue; }
            var dt = ext[i][0] - now;
            if (dt < 0) { dt = -dt; }
            if (dt < bestDt) { bestDt = dt; high = ext[i][0]; }
        }
        if (high != null) {
            var c = TideMath.coefficient(high);
            if (c != null) { text += " C" + c; }
        }
        return text;
    }
}
