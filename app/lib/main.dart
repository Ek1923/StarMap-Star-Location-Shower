import 'package:flutter/material.dart';

import 'ui/app.dart';

/// StarMap. See which stars are above you right now.
///
/// There is no network code in this app. Everything it shows is computed on the device from the
/// clock, your latitude and longitude, and a star catalogue built into it - so it works in a
/// field at night with no signal, which is where a sky app is actually used.
void main() => runApp(const StarMapApp());
