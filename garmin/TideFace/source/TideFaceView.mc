import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Analog face after the Venu's default: numerals, minute ticks, thin white
// hands, four complication places (heart top, steps right, date left, wind
// bottom). Two things the default can't do:
//
//  - The background is the tide: a dark water fill whose surface sits between
//    the current cycle's low water (bottom of the screen) and high water
//    (top), Pornic harmonics computed on-watch — no network, no phone.
//  - A fourth needle, cyan, points straight up while the tide rises and
//    straight down while it falls.
//
// Wind is not fetched here either: the face subscribes to the "Moutiers wind"
// complication the Wind Station widget publishes ("12.3kn NW"), refreshed by
// that widget's 15-minute background service.
class TideFaceView extends WatchUi.WatchFace {

    const FRENCH_DAYS = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];
    const WATER = 0x0A2A44;      // fill below the tide line
    const WATERLINE = 0x2E7EA6;  // the line itself
    const NEEDLE = 0x00AAFF;     // tide-direction needle

    var _sleep as Lang.Boolean = false;
    var _windId = null;          // Complications.Id of "Moutiers wind"
    var _wind as Lang.String or Null = null;
    var _windRetry as Lang.Number = 0;
    // [computedAt, frac 0..1 (low..high water), rising] — refreshed every
    // 10 min; extremes over ±9 h bracket the current cycle whatever the hour.
    var _tide as Lang.Array or Null = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onShow() as Void {
        _subscribeWind();
    }

    function onEnterSleep() as Void {
        _sleep = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleep = false;
        WatchUi.requestUpdate();
    }

    // MARK: Wind complication

    function _subscribeWind() as Void {
        if (!(Toybox has :Complications)) { return; }
        try {
            Toybox.Complications.registerComplicationChangeCallback(
                self.method(:onComplicationChanged));
            var it = Toybox.Complications.getComplications();
            var c = it.next();
            while (c != null) {
                if (c.longLabel != null && c.longLabel.equals("Moutiers wind")) {
                    _windId = c.complicationId;
                    Toybox.Complications.subscribeToUpdates(_windId);
                    break;
                }
                c = it.next();
            }
        } catch (e) {
            _windId = null;
        }
    }

    function onComplicationChanged(id as Toybox.Complications.Id) as Void {
        WatchUi.requestUpdate();
    }

    function _windText() as Lang.String or Null {
        // The Wind Station widget may not have published yet when the face
        // first looks (fresh install, reboot) — look again every ~5 minutes
        // until the complication exists.
        if (_windId == null) {
            _windRetry++;
            if (_windRetry >= 5) {
                _windRetry = 0;
                _subscribeWind();
            }
        }
        if (_windId == null) { return _wind; }
        try {
            var c = Toybox.Complications.getComplication(_windId);
            if (c.value != null) { _wind = c.value.toString(); }
        } catch (e) {}
        return _wind;
    }

    // MARK: Tide state

    function _tideState() as Lang.Array {
        var now = Time.now().value();
        if (_tide != null && now - _tide[0] < 600) { return _tide; }
        var h0 = TideMath.table(now);
        var ext = TideMath.extremes(TideMath.PORT_PORNIC,
                                    now - 9 * 3600, now + 9 * 3600, 1200);
        var prev = null;
        var next = null;
        for (var i = 0; i < ext.size(); i++) {
            if (ext[i][0] <= now) { prev = ext[i]; }
            else if (next == null) { next = ext[i]; }
        }
        // Level and direction from the SAME extremes so the arrow and the
        // water can never disagree: the tide is rising exactly when the next
        // extreme is a high water.
        var rising = next != null ? next[2]
                                  : TideMath.table(now + 300) > h0;
        var frac = 0.5;
        if (prev != null && next != null) {
            var lo = prev[1] < next[1] ? prev[1] : next[1];
            var hi = prev[1] < next[1] ? next[1] : prev[1];
            if (hi - lo > 0.1) {
                frac = (h0 - lo) / (hi - lo);
                if (frac < 0.0) { frac = 0.0; }
                if (frac > 1.0) { frac = 1.0; }
            }
        }
        _tide = [now, frac, rising];
        return _tide;
    }

    // MARK: Rendering

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_sleep) {
            // AMOLED always-on budget: hands and hour dots only, dimmed.
            _drawTicks(dc, cx, cy, w, true);
            _drawHands(dc, cx, cy, h, Graphics.COLOR_DK_GRAY);
            return;
        }

        var tide = _tideState();

        // Water first, everything else on top. The surface runs 92 % of the
        // height (low water) up to 8 % (high water).
        var waterY = cy + ((0.42 - 0.84 * tide[1]) * h).toNumber();
        dc.setColor(WATER, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, waterY, w, h - waterY);
        dc.setColor(WATERLINE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, waterY - 1, w, 3);

        _drawTicks(dc, cx, cy, w, false);
        _drawNumerals(dc, cx, cy, w);
        _drawHeart(dc, cx, cy - 92);
        _drawSteps(dc, cx + 92, cy);
        _drawDate(dc, cx - 84, cy);
        _drawWind(dc, cx, cy + 92);
        _drawTideArrow(dc, w, cx, cy, waterY, tide[2] as Lang.Boolean);
        _drawHands(dc, cx, cy, h, Graphics.COLOR_WHITE);
    }

    // Minute track like the default face: a dot per minute, the tiny gray
    // "05"…"60" numerals every five, tilted tangentially along the bezel.
    // The venu2plus has no vector fonts (getVectorFont/drawRadialText need
    // them), so the digits are drawn as rotated stroke polylines instead.
    function _drawTicks(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                        w as Lang.Number, sleeping as Lang.Boolean) as Void {
        var rDot = w * 478 / 1000;
        var rNum = w * 462 / 1000;
        for (var m = 0; m < 60; m++) {
            var a = m * Math.PI / 30.0;
            if (m % 5 == 0) {
                if (sleeping) {
                    dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(cx + rDot * Math.sin(a), cy - rDot * Math.cos(a), 2);
                    continue;
                }
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                // Glyph "up" points outward on the top half, inward on the
                // bottom half, so every number reads without standing on
                // its head — same trick as the original face.
                var bottom = m > 15 && m < 45;
                var rot = bottom ? a + Math.PI : a;
                _minuteLabel(dc, m == 0 ? 60 : m,
                             cx + rNum * Math.sin(a), cy - rNum * Math.cos(a), rot);
            } else if (!sleeping) {
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx + rDot * Math.sin(a), cy - rDot * Math.cos(a), 1);
            }
        }
    }

    // Rounded stroke digits 0-6 on an 8x14 grid — all the minute track needs.
    // Curves are short polyline runs, so the same rotate-and-draw renderer
    // handles them.
    const DIGIT_STROKES = [
        [[[-3, -3], [-2, -5.2], [0, -6], [2, -5.2], [3, -3], [3, 3],
          [2, 5.2], [0, 6], [-2, 5.2], [-3, 3], [-3, -3]]],                  // 0
        [[[-2, -3.5], [0.5, -6], [0.5, 6]]],                                 // 1
        [[[-3, -3.5], [-2, -5.4], [0, -6], [2, -5.4], [3, -3.5], [3, -2],
          [-2.6, 4.2], [-3, 6], [3, 6]]],                                    // 2
        [[[-3, -4.5], [-1.5, -6], [1, -6], [3, -4.4], [3, -1.8], [0.8, 0],
          [3, 1.8], [3, 4.4], [1, 6], [-1.5, 6], [-3, 4.5]]],                // 3
        [[[1.2, -6], [-3, 0.8], [3, 0.8]], [[1.2, -6], [1.2, 6]]],           // 4
        [[[3, -6], [-2.6, -6], [-2.8, -0.6], [-1, -1.5], [1, -1.5],
          [3, 0.2], [3, 3.2], [1.6, 5.4], [-1, 6], [-3, 4.6]]],              // 5
        [[[2.4, -6], [-0.5, -5], [-2.4, -2], [-3, 1.2], [-2.6, 4],
          [-1, 6], [1, 6], [3, 4.6], [3, 2], [1.4, 0.2], [-1, 0],
          [-2.9, 1.8]]]                                                      // 6
    ];

    // Two-digit label centered on (x, y), rotated by `rot` radians. Scaled
    // down and hairline-thin so the track stays in the background, clear of
    // the big hour numerals.
    function _minuteLabel(dc as Graphics.Dc, value as Lang.Number,
                          x as Lang.Float or Lang.Double, y as Lang.Float or Lang.Double,
                          rot as Lang.Float or Lang.Double) as Void {
        var k = 0.75;
        var s = Math.sin(rot);
        var c = Math.cos(rot);
        dc.setPenWidth(1);
        var digits = [value / 10, value % 10];
        for (var d = 0; d < 2; d++) {
            var offX = d == 0 ? -4.5 : 4.5;   // digit centers along the baseline
            var strokes = DIGIT_STROKES[digits[d]];
            for (var i = 0; i < strokes.size(); i++) {
                var line = strokes[i];
                for (var j = 1; j < line.size(); j++) {
                    var ax = line[j - 1][0] * k + offX;
                    var ay = line[j - 1][1] * k;
                    var bx = line[j][0] * k + offX;
                    var by = line[j][1] * k;
                    dc.drawLine(x + ax * c - ay * s, y + ax * s + ay * c,
                                x + bx * c - by * s, y + bx * s + by * c);
                }
            }
        }
    }

    function _drawNumerals(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                           w as Lang.Number) as Void {
        var r = w * 36 / 100;
        var f = Graphics.FONT_SMALL;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var n = 1; n <= 12; n++) {
            var a = n * Math.PI / 6.0;
            var x = cx + r * Math.sin(a);
            var y = cy - r * Math.cos(a);
            if (n < 10) {
                dc.drawText(x, y, f, n.toString(),
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                continue;
            }
            // Two-digit numerals get manual kerning — the bitmap font's own
            // tracking is wider than the original face's.
            var d1 = "1";
            var d2 = (n % 10).toString();
            var kern = 4;
            var w1 = dc.getTextWidthInPixels(d1, f);
            var total = w1 + dc.getTextWidthInPixels(d2, f) - kern;
            dc.drawText(x - total / 2, y, f, d1,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(x - total / 2 + w1 - kern, y, f, d2,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Heart rate with the default face's rainbow ring and a drawn heart —
    // Garmin fonts have no ♥ glyph (they render tofu).
    function _drawHeart(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number) as Void {
        var colors = [Graphics.COLOR_RED, Graphics.COLOR_ORANGE, Graphics.COLOR_YELLOW,
                      Graphics.COLOR_GREEN, Graphics.COLOR_BLUE, Graphics.COLOR_PURPLE];
        dc.setPenWidth(5);
        for (var i = 0; i < 6; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, y, 36, Graphics.ARC_CLOCKWISE, 90 - i * 60, 90 - (i + 1) * 60);
        }
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 5, y - 15, 6);
        dc.fillCircle(x + 5, y - 15, 6);
        dc.fillPolygon([[x - 10, y - 12], [x + 10, y - 12], [x, y - 1]]);
        var hr = Activity.getActivityInfo().currentHeartRate;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + 12, Graphics.FONT_XTINY, hr == null ? "--" : hr.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Steps with a goal-progress ring, like the default face's cyan arc.
    function _drawSteps(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps == null ? 0 : info.steps;
        var goal = info.stepGoal == null || info.stepGoal == 0 ? 10000 : info.stepGoal;
        dc.setPenWidth(5);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, 36);
        var frac = steps.toFloat() / goal;
        if (frac > 1.0) { frac = 1.0; }
        if (frac > 0.01) {
            dc.setColor(0x00D0D0, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, y, 36, Graphics.ARC_CLOCKWISE, 90, 90 - (frac * 360).toNumber());
        }
        dc.setPenWidth(1);
        // Footprints: two offset soles with a toe dot each.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 8, y - 17, 6, 11, 3);
        dc.fillCircle(x - 5, y - 21, 2);
        dc.fillRoundedRectangle(x + 2, y - 13, 6, 11, 3);
        dc.fillCircle(x + 5, y - 17, 2);
        dc.drawText(x, y + 10, Graphics.FONT_XTINY, steps.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "Lun 24" — French like the rest of dad's watch.
    function _drawDate(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number) as Void {
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = FRENCH_DAYS[g.day_of_week - 1] + " " + g.day;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_TINY, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Moutiers wind from the Wind Station complication: "12.3kn NW" split
    // over two lines inside the ring.
    function _drawWind(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number) as Void {
        dc.setPenWidth(4);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, 36);
        dc.setPenWidth(1);
        var text = _windText();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (text == null) {
            dc.drawText(x, y, Graphics.FONT_TINY, "--",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var space = text.find(" ");
        var speed = space == null ? text : text.substring(0, space);
        var dir = space == null ? "" : text.substring(space + 1, text.length());
        dc.drawText(x, y - 9, Graphics.FONT_XTINY, speed,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + 11, Graphics.FONT_XTINY, dir,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A small arrow riding the waterline: pointing up while the tide comes
    // in, down while it goes out. The x position is picked so the arrow never
    // sits on a complication — center first, then sliding outward until the
    // spot is clear of every slot circle at the waterline's current height.
    function _drawTideArrow(dc as Graphics.Dc, w as Lang.Number,
                            cx as Lang.Number, cy as Lang.Number,
                            waterY as Lang.Number, rising as Lang.Boolean) as Void {
        // Slot circles as [x, y, clearance] — clearance is the ring radius
        // plus the arrow's half-width and a margin.
        var blockers = [
            [cx, cy - 92, 50],       // heart
            [cx + 92, cy, 50],       // steps
            [cx - 84, cy, 56],       // date text, a bit wider
            [cx, cy + 92, 50]        // wind
        ];
        var candidates = [0, -70, 70, -110, 110, -145, 145];
        var half = w / 2;
        var x = cx;
        for (var i = 0; i < candidates.size(); i++) {
            var cand = cx + candidates[i];
            // Stay inside the round screen at this height.
            var dy = waterY - cy;
            var chord2 = half * half - dy * dy;
            if (chord2 < 900) { continue; }
            if ((cand - cx).abs() > Math.sqrt(chord2) - 26) { continue; }
            var clear = true;
            for (var b = 0; b < blockers.size(); b++) {
                var bx = blockers[b][0];
                var by = blockers[b][1];
                var dx = cand - bx;
                var dby = waterY - by;
                if (dx * dx + dby * dby < blockers[b][2] * blockers[b][2]) {
                    clear = false;
                    break;
                }
            }
            if (clear) {
                x = cand;
                break;
            }
        }
        dc.setColor(NEEDLE, Graphics.COLOR_TRANSPARENT);
        if (rising) {
            dc.fillPolygon([[x, waterY - 14], [x - 9, waterY + 3], [x + 9, waterY + 3]]);
        } else {
            dc.fillPolygon([[x, waterY + 14], [x - 9, waterY - 3], [x + 9, waterY - 3]]);
        }
    }

    // The default face's hands: plain rounded bars detached from the center
    // for hour and minute, and — while the screen is awake — a skinny seconds
    // needle carrying a small open ring near its tip. AMOLED faces repaint
    // every second in high power and once a minute in always-on, which is
    // exactly when the native face shows and hides its seconds hand too.
    function _drawHands(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                        h as Lang.Number, color as Graphics.ColorType) as Void {
        var clock = System.getClockTime();
        var minuteA = clock.min * Math.PI / 30.0;
        var hourA = (clock.hour % 12 + clock.min / 60.0) * Math.PI / 6.0;
        _hand(dc, cx, cy, hourA, 34, h * 28 / 100, 8, color);
        // The minute hand is hollow on the original: a white outline around a
        // dark core.
        var mLen = h * 46 / 100;
        _hand(dc, cx, cy, minuteA, 34, mLen, 7, color);
        _bar(dc, cx, cy, minuteA, 34 + 3, mLen - 3, 3, Graphics.COLOR_BLACK);
        if (!_sleep) {
            var secondA = clock.sec * Math.PI / 30.0;
            var sLen = h * 45 / 100;
            _hand(dc, cx, cy, secondA, 14, sLen - 14, 2, color);
            var rx = cx + (sLen - 7) * Math.sin(secondA);
            var ry = cy - (sLen - 7) * Math.cos(secondA);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(rx, ry, 7);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawCircle(rx, ry, 7);
            dc.setPenWidth(1);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 3);
    }

    // One bar from rIn to rOut along `angle` (radians clockwise from 12),
    // rounded at both ends, with a thin dark halo so it separates from
    // whatever it crosses — the native hands read that way too.
    function _hand(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                   angle as Lang.Float or Lang.Double,
                   rIn as Lang.Number, rOut as Lang.Number,
                   width as Lang.Number, color as Graphics.ColorType) as Void {
        _bar(dc, cx, cy, angle, rIn, rOut, width + 3, Graphics.COLOR_BLACK);
        _bar(dc, cx, cy, angle, rIn, rOut, width, color);
    }

    function _bar(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
                  angle as Lang.Float or Lang.Double,
                  rIn as Lang.Number, rOut as Lang.Number,
                  width as Lang.Number, color as Graphics.ColorType) as Void {
        var s = Math.sin(angle);
        var c = Math.cos(angle);
        var hw = width / 2.0;
        var x0 = cx + rIn * s;
        var y0 = cy - rIn * c;
        var x1 = cx + rOut * s;
        var y1 = cy - rOut * c;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x0 - hw * c, y0 - hw * s],
            [x0 + hw * c, y0 + hw * s],
            [x1 + hw * c, y1 + hw * s],
            [x1 - hw * c, y1 - hw * s]
        ]);
        dc.fillCircle(x0, y0, hw);
        dc.fillCircle(x1, y1, hw);
    }
}
