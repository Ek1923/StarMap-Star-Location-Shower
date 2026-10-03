import 'package:flutter/material.dart';

import 'ui/app.dart';

/// StarMap. See which stars are above you right now.
///
/// Everything it shows is computed on the device from the clock, your latitude and longitude, and
/// a star catalogue built into it - so it works in a field at night with no signal, which is
/// where a sky app is actually used.
///
/// With a connection it also asks NASA/JPL Horizons for the same positions and uses those
/// instead, because that is the ephemeris this app's accuracy is measured against. The request
/// carries a body code and a timestamp; your coordinates stay here, and the correction for where
/// you stand is applied on the device. See lib/net/horizons.dart.
void main() => runApp(const StarMapApp());
