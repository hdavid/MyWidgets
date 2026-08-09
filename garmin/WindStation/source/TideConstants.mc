import Toybox.Lang;

// GENERATED — do not edit by hand (scratchpad/gen_tide_mc.py in the session
// notes). Same numbers the Apple apps bundle: PORNIC from the OpenCPN/XTide
// harmonic catalog with phases converted to the Greenwich convention, the
// height calibration fitted against maree.info's table (week of 2026-08-09,
// max residual 0.17 m), and Brest's four main semi-diurnal constituents
// (windguru set) for the French coefficient.
module TideConstants {

    // Heights: table_m = (sum_cm / 100 + DATUM) * SCALE + BIAS
    const DATUM = 3.57;
    const SCALE = 0.973;
    const BIAS = 0.284;
    // Thresholds on the table scale: Les Moutiers, La Bernerie.
    const THRESHOLDS = [3.8, 3.5];
    // Coefficient: C = 100 * brest_hw_m / 3.05 - COEF_BIAS, clamped 20..120.
    const BREST_UNIT = 3.05;
    const COEF_BIAS = 7.15;

    // PORNIC: 20 constituents
    const PORNIC_AMP = [4.78, 0.55, 6.2, 17.16, 4.99, 1.22, 174.8, 21.9, 9.6, 9.0, 5.76, 36.3, 6.85, 7.0, 2.07, 2.2, 0.51, 63.5, 2.3, 3.74];
    const PORNIC_PHASE = [87.1, 79.41, 79.96, 137.92, 104.47, 138.54, 105.02, 43.03, 351.58, 133.02, 87.03, 86.56, 86.49, 327.06, 80.04, 280.6, 137.96, 138.0, 264.96, 138.04];
    const PORNIC_N = [2, -2, 0, 2, 0, 0, 1, 2, 0, -1, 0, 0, 1, 1, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 1, 0, -1, 0, 0, 2, 1, -2, 1, 0, 0, 2, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 4, -1, 0, 1, 0, 0, 4, 2, -2, 0, 0, 0, 2, -2, 2, 0, 0, 0, 2, -1, 0, 1, 0, 0, 2, -1, 2, -1, 0, 0, 1, -1, 0, 0, 0, 0, 1, 1, -2, 0, 0, 0, 1, -2, 0, 1, 0, 0, 2, 2, -1, 0, 0, -1, 2, 2, -2, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 2, -3, 0, 0, 1];
    const PORNIC_OFFSET = [0, 90, 90, 0, 180, 180, 0, 0, 0, 0, 0, 0, 0, -90, -90, -90, 180, 0, 0, 0];
    const PORNIC_NODAL = [1, 5, 2, 4, 1, 1, 1, 9, 9, 1, 1, 1, 1, 3, 0, 3, 0, 0, 0, 0];

    // BREST: 4 constituents
    const BREST_AMP = [22.25, 218.97, 43.13, 81.24];
    const BREST_PHASE = [136.35, 100.53, 82.25, 138.79];
    const BREST_N = [2, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2, -1, 0, 1, 0, 0, 2, 2, -2, 0, 0, 0];
    const BREST_OFFSET = [0, 0, 0, 0];
    const BREST_NODAL = [4, 1, 1, 0];
}
