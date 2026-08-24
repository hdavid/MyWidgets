import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TideFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new TideFaceView()];
    }

    // Slot assignments changed in the Connect IQ phone app — repaint.
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
