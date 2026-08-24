import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Touch on the face: pressing (or tapping) the wind slot — or the tide dial —
// launches the Wind Station app via its published complication, which is the
// only cross-app door Connect IQ offers a watch face.
class TideFaceDelegate extends WatchUi.WatchFaceDelegate {

    var _view as TideFaceView;

    function initialize(view as TideFaceView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        return _openSlot(clickEvent);
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        return _openSlot(clickEvent);
    }

    function _openSlot(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        var xy = clickEvent.getCoordinates();
        var s = System.getDeviceSettings();
        var cx = s.screenWidth / 2;
        var cy = s.screenHeight / 2;
        // Same slot geometry as the view's onUpdate.
        var positions = [[cx, cy - 92], [cx + 92, cy], [cx - 84, cy], [cx, cy + 92]];
        for (var i = 0; i < 4; i++) {
            var dx = xy[0] - positions[i][0];
            var dy = xy[1] - positions[i][1];
            if (dx * dx + dy * dy > 44 * 44) { continue; }
            return _view.openSlotApp(i);
        }
        return false;
    }
}
