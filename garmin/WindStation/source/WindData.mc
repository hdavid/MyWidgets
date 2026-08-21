import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

// Talks to the same Grafana /api/ds/query endpoints as the Apple widgets
// (Shared/WindData.swift), batching each station's metrics into one request —
// round-trips matter on a watch. Stations are baked in (private, sideloaded
// app; rebuild to change them); only the per-station tokens are settings,
// entered via Garmin Connect on the paired phone. Queries mirror
// local-config/grafana.json: both sites are now Ecowitt WittBoy (WS90)
// stations, so the measurement names match and only the host and the
// host differs. Both convert km/h to knots via * 0.54.
//
// The site/masking multiplier is NOT applied here. It is applied once,
// upstream, in the openHAB conversion rule on each Pi, so InfluxDB already
// holds corrected km/h. The explicit * 1.0 is a reminder: putting a real
// factor back here would double-correct.
//
// The headline "avg" is a 5-minute mean — a lone instant reading is too
// jumpy to act on. It reads the one_minute retention policy's downsampled
// mean_value field (what the Grafana dashboards show) rather than averaging
// raw autogen samples. "inst" keeps the latest raw instant sample for the
// widget view's small "now" line and for the measured-at timestamp (the
// mean's own timestamp is the window START, ~5 min stale).
//
// The glance fetches only the wind refs; the widget view adds temperature,
// pressure (+3h-ago value for the trend arrow, Moutiers only — Bernerie has
// no barometer; Moutiers' comes from a SEPARATE 433 MHz sensor, P12_C0, not
// from the weather station) and the 1h/1min wind series for the sparkline.
(:background, :glance)
module WindData {

    const STATIONS = [
        {
            "label" => "MOUTIERS",
            "base" => "https://moutiers.motscousus.com/grafana",
            "tokenKey" => "tokenMoutiers",
            "datasourceId" => 1,
            "avg" => "SELECT mean(mean_value) * 1.0 * 0.54 FROM one_minute.ws90_weather_wind_avg_km_h WHERE time > now() - 5m",
            "inst" => "SELECT last(value) * 1.0 * 0.54 FROM autogen.ws90_weather_wind_avg_km_h",
            "gust" => "SELECT last(value) * 1.0 * 0.54 FROM autogen.ws90_weather_wind_max_km_h",
            "dir" => "SELECT last(value) FROM autogen.ws90_weather_wind_dir_deg",
            "temp" => "SELECT last(value) FROM autogen.ws90_weather_temperature_c",
            "pressure" => "SELECT last(value) FROM autogen.P12_C0_pressure_hPa",
            "ptrend" => "SELECT first(value) FROM autogen.P12_C0_pressure_hPa WHERE time > now() - 3h",
            "series" => "SELECT mean(value) * 1.0 * 0.54 FROM autogen.ws90_weather_wind_avg_km_h WHERE time > now() - 1h GROUP BY time(1m) fill(none)"
        },
        {
            "label" => "BERNERIE",
            "base" => "https://bernerie.motscousus.com/grafana",
            "tokenKey" => "tokenBernerie",
            "datasourceId" => 1,
            "avg" => "SELECT mean(mean_value) * 1.0 * 0.54 FROM one_minute.ws90_weather_wind_avg_km_h WHERE time > now() - 5m",
            "inst" => "SELECT last(value) * 1.0 * 0.54 FROM autogen.ws90_weather_wind_avg_km_h",
            "gust" => "SELECT last(value) * 1.0 * 0.54 FROM autogen.ws90_weather_wind_max_km_h",
            "dir" => "SELECT last(value) FROM autogen.ws90_weather_wind_dir_deg",
            "temp" => "SELECT last(value) FROM autogen.ws90_weather_temperature_c",
            "pressure" => null,
            "ptrend" => null,
            "series" => "SELECT mean(value) * 1.0 * 0.54 FROM autogen.ws90_weather_wind_avg_km_h WHERE time > now() - 1h GROUP BY time(1m) fill(none)"
        }
    ];

    // ref -> station query key; A-C plus H are the glance/background set
    // (light response), D-G the widget-view extras. H rides along in the
    // light set too: it is the freshest sample, so it supplies mAt.
    const REFS = {
        "A" => "avg", "B" => "gust", "C" => "dir",
        "D" => "temp", "E" => "pressure", "F" => "ptrend", "G" => "series",
        "H" => "inst"
    };
    const LIGHT_REFS = ["A", "B", "C", "H"];
    const FULL_REFS = ["A", "B", "C", "D", "E", "F", "G", "H"];

    // Kick off the request for one station; cb is a Method(responseCode, data)
    // owned by the calling view, invoked when the response arrives.
    function request(station as Lang.Number, cb as Lang.Method, full as Lang.Boolean) as Void {
        var s = STATIONS[station];
        var token = Application.Properties.getValue(s["tokenKey"]);
        if (token == null || token.equals("")) {
            cb.invoke(-1000, null); // sentinel: not configured
            return;
        }
        var refs = full ? FULL_REFS : LIGHT_REFS;
        var queries = [];
        for (var i = 0; i < refs.size(); i++) {
            var q = s[REFS[refs[i]]];
            if (q != null) {
                queries.add({
                    "refId" => refs[i],
                    "datasourceId" => s["datasourceId"],
                    "rawQuery" => true,
                    "query" => q,
                    "resultFormat" => "time_series"
                });
            }
        }
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Authorization" => "Bearer " + token,
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(
            s["base"] + "/api/ds/query",
            { "queries" => queries, "from" => "now-3h", "to" => "now" },
            options, cb);
    }

    // Parse a 200 response into a snapshot dictionary or null. Only the wind
    // refs are required; the extras stay null when absent (light response,
    // station without the sensor). persist=false in the background service,
    // which hands its snapshots to the app via Background.exit instead.
    function parse(station as Lang.Number, data, persist as Lang.Boolean) as Lang.Dictionary or Null {
        var avgCol = _columns(data, "A");
        if (avgCol == null) { return null; }
        // mAt from the instant ref: the 5-min mean's timestamp (ref A) is the
        // window start, so it would read ~5 min stale even on fresh data.
        var instCol = _columns(data, "H");
        var snap = {
            "avg" => _first(avgCol),
            "gust" => _value(data, "B"),
            "dir" => _value(data, "C"),
            "temp" => _value(data, "D"),
            "pressure" => _value(data, "E"),
            "ptrend" => _value(data, "F"),
            "series" => _series(data, "G"),
            "inst" => instCol != null ? _first(instCol) : null,
            "mAt" => instCol != null ? _firstTime(instCol) : _firstTime(avgCol),
            "at" => Time.now().value()
        };
        if (snap["avg"] == null) { return null; }
        if (persist) {
            Application.Storage.setValue("snap" + station, snap);
        }
        return snap;
    }

    // results.<ref>.frames[0].data.values -> [[times],[values]] or null.
    function _columns(data, ref as Lang.String) as Lang.Array or Null {
        if (!(data instanceof Lang.Dictionary)) { return null; }
        var results = data["results"];
        if (!(results instanceof Lang.Dictionary)) { return null; }
        var r = results[ref];
        if (!(r instanceof Lang.Dictionary)) { return null; }
        var frames = r["frames"];
        if (!(frames instanceof Lang.Array) || frames.size() == 0) { return null; }
        var frame = frames[0];
        if (!(frame instanceof Lang.Dictionary)) { return null; }
        var d = frame["data"];
        if (!(d instanceof Lang.Dictionary)) { return null; }
        var values = d["values"];
        if (!(values instanceof Lang.Array) || values.size() < 2) { return null; }
        return values;
    }

    function _first(cols as Lang.Array) {
        var col = cols[1];
        if (!(col instanceof Lang.Array) || col.size() == 0) { return null; }
        return col[0];
    }

    function _firstTime(cols as Lang.Array) {
        var col = cols[0];
        if (!(col instanceof Lang.Array) || col.size() == 0) { return null; }
        return col[0]; // epoch ms
    }

    function _value(data, ref as Lang.String) {
        var cols = _columns(data, ref);
        if (cols == null) { return null; }
        return _first(cols);
    }

    function _series(data, ref as Lang.String) as Lang.Array or Null {
        var cols = _columns(data, ref);
        if (cols == null) { return null; }
        var col = cols[1];
        if (!(col instanceof Lang.Array) || col.size() < 2) { return null; }
        var out = [];
        for (var i = 0; i < col.size(); i++) {
            if (col[i] != null) { out.add(col[i].toFloat()); }
        }
        return out.size() >= 2 ? out : null;
    }

    function stored(station as Lang.Number) as Lang.Dictionary or Null {
        return Application.Storage.getValue("snap" + station);
    }

    // 315 -> "NW"
    function cardinal(deg) as Lang.String {
        if (deg == null) { return "--"; }
        var names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        var idx = (((deg.toFloat() + 11.25) / 22.5).toNumber()) % 16;
        return names[idx];
    }

    function knots(v) as Lang.String {
        if (v == null) { return "--"; }
        return v.toFloat().format("%.1f");
    }

    // Age of a snapshot in minutes, for the staleness footer.
    function ageMinutes(snap) as Lang.Number or Null {
        if (!(snap instanceof Lang.Dictionary)) { return null; }
        var at = snap["at"];
        if (!(at instanceof Lang.Number)) { return null; }
        return (Time.now().value() - at) / 60;
    }
}
