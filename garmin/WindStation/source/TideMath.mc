import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// Harmonic tide synthesis — a Monkey C port of the engine validated against
// maree.info (times within ±19 min, heights within the fitted calibration's
// 17 cm residual). Everything runs on Double: the Julian-day epoch arithmetic
// destroys 32-bit floats.
module TideMath {

    const DEG = 0.017453292519943295d;

    // Mean longitudes (degrees) and mean lunar time at epoch-seconds t.
    // Returns [tau, s, h, p, N, p1].
    function astro(tsec as Lang.Number or Lang.Long) as Lang.Array {
        var jd = tsec.toDouble() / 86400.0d + 2440587.5d;
        var t = (jd - 2451545.0d) / 36525.0d;
        var s = 218.3164477d + 481267.88123421d * t;
        var h = 280.46646d + 36000.76983d * t;
        var p = 83.3532465d + 4069.0137287d * t;
        var n = 125.0445479d - 1934.1362891d * t;
        var p1 = 282.9373400d + 1.7195366d * t;
        var f = jd + 0.5d;
        var ut = (f - Math.floor(f)) * 24.0d;
        return [15.0d * ut + h - s, s, h, p, n, p1];
    }

    // Doodson's nodal corrections; returns [f, u_degrees] for a code from
    // TideConstants *_NODAL (0 none, 1 m2, 2 k1, 3 o1, 4 k2, 5 j1, 6 mm,
    // 7 mf, 8 m3, 9 m4, 10 m6, 11 m8).
    function nodal(code as Lang.Number, n as Lang.Double) as Lang.Array {
        if (code == 0) { return [1.0d, 0.0d]; }
        var c1 = Math.cos(n * DEG);
        var c2 = Math.cos(2.0d * n * DEG);
        var c3 = Math.cos(3.0d * n * DEG);
        var s1 = Math.sin(n * DEG);
        var s2 = Math.sin(2.0d * n * DEG);
        var s3 = Math.sin(3.0d * n * DEG);
        var mf = 1.0004d - 0.0373d * c1 + 0.0002d * c2;
        var mu = -2.14d * s1;
        switch (code) {
        case 1: return [mf, mu];
        case 2: return [1.0060d + 0.1150d * c1 - 0.0088d * c2 + 0.0006d * c3,
                        -8.86d * s1 + 0.68d * s2 - 0.07d * s3];
        case 3: return [1.0089d + 0.1871d * c1 - 0.0147d * c2 + 0.0014d * c3,
                        10.80d * s1 - 1.34d * s2 + 0.19d * s3];
        case 4: return [1.0241d + 0.2863d * c1 + 0.0083d * c2 - 0.0015d * c3,
                        -17.74d * s1 + 0.68d * s2 - 0.04d * s3];
        case 5: return [1.0129d + 0.1676d * c1 - 0.0170d * c2 + 0.0016d * c3,
                        -12.94d * s1 + 1.34d * s2 - 0.19d * s3];
        case 6: return [1.0000d - 0.1300d * c1 + 0.0013d * c2, 0.0d];
        case 7: return [1.0429d + 0.4135d * c1 - 0.0040d * c2,
                        -23.74d * s1 + 2.68d * s2 - 0.38d * s3];
        case 8: return [Math.pow(mf, 1.5d), 1.5d * mu];
        case 9: return [mf * mf, 2.0d * mu];
        case 10: return [Math.pow(mf, 3.0d), 3.0d * mu];
        case 11: return [Math.pow(mf, 4.0d), 4.0d * mu];
        }
        return [1.0d, 0.0d];
    }

    // Sea level in cm above MSL for one constituent set at epoch-seconds t.
    function heightCm(amp as Lang.Array, phase as Lang.Array, n as Lang.Array,
                      offset as Lang.Array, nodalCodes as Lang.Array,
                      tsec as Lang.Number or Lang.Long) as Lang.Double {
        var ctx = makeCtx(amp, phase, n, offset, nodalCodes, tsec);
        return evalCtx(ctx, tsec);
    }

    // Batch context: every astronomical argument is linear in time, so each
    // constituent folds into fAmp·cos(c0 + speed·dtHours) — one astro+nodal
    // evaluation per batch instead of per sample, which is what keeps the
    // synthesis inside the CIQ watchdog budget.
    // ctx = [t0, c0[], speedDegPerHour[], fAmp[]].
    function makeCtx(amp as Lang.Array, phase as Lang.Array, n as Lang.Array,
                     offset as Lang.Array, nodalCodes as Lang.Array,
                     t0 as Lang.Number or Lang.Long) as Lang.Array {
        var a0 = astro(t0);
        var a1 = astro(t0 + 3600);
        var k = amp.size();
        var c0 = new [k];
        var speed = new [k];
        var fAmp = new [k];
        for (var i = 0; i < k; i++) {
            var j = 6 * i;
            var v0 = n[j] * a0[0] + n[j + 1] * a0[1] + n[j + 2] * a0[2]
                   + n[j + 3] * a0[3] + n[j + 4] * a0[4] + n[j + 5] * a0[5];
            var v1 = n[j] * a1[0] + n[j + 1] * a1[1] + n[j + 2] * a1[2]
                   + n[j + 3] * a1[3] + n[j + 4] * a1[4] + n[j + 5] * a1[5];
            var fu = nodal(nodalCodes[i], a0[4]);
            c0[i] = (v0 + offset[i] + fu[1] - phase[i]) * DEG;
            speed[i] = (v1 - v0) * DEG;
            fAmp[i] = fu[0] * amp[i].toDouble();
        }
        return [t0, c0, speed, fAmp];
    }

    function evalCtx(ctx as Lang.Array, tsec as Lang.Number or Lang.Long) as Lang.Double {
        var dt = (tsec - ctx[0]).toDouble() / 3600.0d;
        var c0 = ctx[1];
        var speed = ctx[2];
        var fAmp = ctx[3];
        var sum = 0.0d;
        for (var i = 0; i < c0.size(); i++) {
            sum += fAmp[i] * Math.cos(c0[i] + speed[i] * dt);
        }
        return sum;
    }

    function pornicCtx(t0 as Lang.Number) as Lang.Array {
        return makeCtx(TideConstants.PORNIC_AMP, TideConstants.PORNIC_PHASE,
                       TideConstants.PORNIC_N, TideConstants.PORNIC_OFFSET,
                       TideConstants.PORNIC_NODAL, t0);
    }

    function brestCtx(t0 as Lang.Number) as Lang.Array {
        return makeCtx(TideConstants.BREST_AMP, TideConstants.BREST_PHASE,
                       TideConstants.BREST_N, TideConstants.BREST_OFFSET,
                       TideConstants.BREST_NODAL, t0);
    }

    // cm above MSL → printed-table metres (calibrated).
    function tableFromCm(cm as Lang.Double) as Lang.Float {
        return ((cm / 100.0d + TideConstants.DATUM) * TideConstants.SCALE
                + TideConstants.BIAS).toFloat();
    }

    // PORNIC height on the printed-table scale — single instants only; batch
    // work goes through pornicCtx/evalCtx.
    function table(tsec as Lang.Number or Lang.Long) as Lang.Float {
        return tableFromCm(heightCm(TideConstants.PORNIC_AMP, TideConstants.PORNIC_PHASE,
                                    TideConstants.PORNIC_N, TideConstants.PORNIC_OFFSET,
                                    TideConstants.PORNIC_NODAL, tsec));
    }

    const PORT_PORNIC = 0;
    const PORT_BREST = 1;

    // Extremes between t0 and t1 by `step`-second sampling with parabolic
    // refinement: array of [tsec, height, isHigh]. Heights are table-metres
    // for PORNIC, raw cm for BREST.
    function extremes(port as Lang.Number, t0 as Lang.Number, t1 as Lang.Number,
                      step as Lang.Number) as Lang.Array {
        var ctx = port == PORT_BREST ? brestCtx(t0) : pornicCtx(t0);
        var pornic = port == PORT_PORNIC;
        var count = (t1 - t0) / step;
        var hs = new [count + 1];
        for (var i = 0; i <= count; i++) {
            var cm = evalCtx(ctx, t0 + i * step);
            hs[i] = pornic ? tableFromCm(cm) : cm.toFloat();
        }
        var out = [];
        for (var i = 1; i < count; i++) {
            var d1 = hs[i] - hs[i - 1];
            var d2 = hs[i + 1] - hs[i];
            if (d1 * d2 <= 0 && d1 != 0) {
                var off = (d1 - d2) != 0 ? 0.5 * (d1 + d2) / (d1 - d2) * step : 0;
                var t = t0 + i * step + off.toNumber();
                var cm = evalCtx(ctx, t);
                out.add([t, pornic ? tableFromCm(cm) : cm.toFloat(), d1 > 0]);
            }
        }
        return out;
    }

    // French coefficient for a high water at epoch-seconds tHigh: nearest
    // Brest SD4 high within ±4 h, scaled by the unit of height. Null when
    // none pairs.
    function coefficient(tHigh as Lang.Number) as Lang.Number or Null {
        var ext = extremes(PORT_BREST, tHigh - 6 * 3600, tHigh + 6 * 3600, 900);
        var best = null;
        var bestDt = 4 * 3600;
        for (var i = 0; i < ext.size(); i++) {
            if (!ext[i][2]) { continue; }
            var dt = ext[i][0] - tHigh;
            if (dt < 0) { dt = -dt; }
            if (dt < bestDt) { bestDt = dt; best = ext[i][1]; }
        }
        if (best == null) { return null; }
        var c = 100.0d * (best.toDouble() / 100.0d) / TideConstants.BREST_UNIT
              - TideConstants.COEF_BIAS;
        var r = Math.round(c).toNumber();
        return r < 20 ? 20 : (r > 120 ? 120 : r);
    }
}
