import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

(:background, :glance)
class WindStationApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) as Void {
        // (Re-)arm the background refresh; safe to call on every launch.
        if (Toybox.System has :ServiceDelegate) {
            Background.registerForTemporalEvent(new Time.Duration(15 * 60));
        }
    }

    // Tide needs no network — recompute and republish whenever we run.
    // NOT called from onStart: updateComplication traps with Out of Bounds
    // before the app is fully started, so callers are the view (onShow) and
    // onBackgroundData, both safely later.
    function publishTide() as Void {
        if (!(Toybox has :Complications)) { return; }
        Toybox.Complications.updateComplication(2, {
            :value => TidePage.complicationValue()
        });
    }

    function getInitialView() {
        var view = new WindStationView();
        return [view, new WindStationDelegate(view)];
    }

    (:glance)
    function getGlanceView() {
        return [new WindStationGlanceView()];
    }

    function getServiceDelegate() {
        return [new WindService()];
    }

    // Snapshots fetched by WindService arrive here in the app context:
    // persist them (views open instantly with fresh data) and update the
    // watch-face complications.
    function onBackgroundData(data) as Void {
        publishTide();
        if (!(data instanceof Lang.Dictionary)) { return; }
        for (var i = 0; i < WindData.STATIONS.size(); i++) {
            var snap = data[i];
            if (snap instanceof Lang.Dictionary) {
                Application.Storage.setValue("snap" + i, snap);
                WindComplication.publish(i, snap);
            }
        }
    }
}
