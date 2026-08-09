import Toybox.Lang;

// Publishes one complication per station (ids match STATIONS indexes) with
// speed + direction, e.g. "12.3kn NW". Public access so Face It and any
// CIQ watch face can subscribe. Guarded: venu2/fenix7x both have CIQ 5.x
// (Complications is 4.2+), but the guard keeps older targets safe.
module WindComplication {

    function publish(station as Lang.Number, snap as Lang.Dictionary) as Void {
        if (!(Toybox has :Complications)) { return; }
        var avg = snap["avg"];
        if (avg == null) { return; }
        var text = WindData.knots(avg) + "kn " + WindData.cardinal(snap["dir"]);
        Toybox.Complications.updateComplication(station, {
            :value => text
        });
    }
}
