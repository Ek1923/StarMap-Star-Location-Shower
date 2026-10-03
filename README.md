# StarMap

**Which stars are above you, right now, from where you are standing.**

A small app that answers four questions and does not pretend to answer any others:

| Screen | What it tells you |
|---|---|
| **Overhead** | Every planet, the Moon and the bright stars, plotted at their real compass bearing and real height above your horizon. The ones under your feet are shown too, greyed, because "behind you" and "set" are different answers. |
| **Energy** | Which planet is actually delivering the most light to you tonight, in lux, ranked. The winner changes from month to month. |
| **Your sign** | Your zodiac sign next to the constellation the Sun is *physically* in today. They disagree by about one whole sign, and the screen explains why. |
| **Moon** | Tonight's phase drawn from the real lit fraction, how far away it is, and when it is next full or new. |

**It works with no signal, and gets sharper with one.**

The app computes the whole sky on the device, instantly, from the clock and your latitude and
longitude. That is the normal path and it never fails: in a dark field with no reception the app
is complete.

When there is a connection it then asks **NASA/JPL Horizons** for the same positions in the
background, one body at a time, and each answer that arrives replaces one computed position. Since
Horizons is the very ephemeris the accuracy table below is measured against, there is no error
left to quote for a body that came from it. Nothing waits on the network, a body that fails keeps
its computed value, and the screen always says which source it used - including when it is half
and half.

### Your location still never leaves the device

Horizons can compute a position for an observer at a given spot on Earth. Asking it to would mean
sending that spot. So the app asks for **geocentric** positions - as seen from the Earth's centre
- and applies the observer correction itself, with the same code the offline path uses. The
request carries a body code and a timestamp. That is all of it.

That only works if the device-side correction reproduces what Horizons would have returned had it
been told where you are, so it is measured rather than assumed. Taking NASA's geocentric figures,
applying the correction here, and comparing against NASA's own topocentric figures for the same
bodies at the same instants:

| | worst disagreement |
|---|---|
| Moon | **0.44″** |
| every other body | 0.29″ to 0.32″ |

The Moon is the one that proves it: its parallax from the Earth's surface reaches a full degree,
twice its own width, so a correction that was wrong would show up here as arcminutes rather than
half an arcsecond. Keeping your coordinates off the network costs nothing.

The release APK therefore declares two capabilities and no more - verified with `aapt2 dump
permissions` on the built binary:

```
uses-permission: android.permission.ACCESS_COARSE_LOCATION
uses-permission: android.permission.INTERNET
```

**The web build never reaches NASA.** Measured: `ssd.jpl.nasa.gov` sends no
`Access-Control-Allow-Origin` header, so a browser blocks the request. That is not a bug to work
around - the offline path is the normal path - but it is why the web build always says positions
were computed here.

---

## How wrong is it?

Every number below is measured against **NASA/JPL's own ephemeris** — 16 comparisons per body,
from four places on Earth (Amsterdam, Istanbul, Sydney, Quito) at four dates across two years.
Reproduce them with `flutter test`; the test prints this table.

| Body | Median error | Worst error |
|---|---|---|
| Moon | **1.9″** | 3.6″ |
| Sun | 12.0″ | 13.2″ |
| Mercury | 12.3″ | 16.2″ |
| Mars | 14.0″ | 16.9″ |
| Venus | 14.3″ | 26.0″ |
| Uranus | 13.2″ | 16.7″ |
| Neptune | 33.0″ | 35.0″ |
| Jupiter | 1.79′ | 2.14′ |
| Saturn | 4.32′ | **4.97′** |

For scale: the full Moon is 31 arcminutes wide, and your little finger at arm's length covers
about 60. The worst body in the table, Saturn, is off by a sixth of a Moon-width. **This app is
more accurate than you can point.**

Other measured figures:

- **Moon distance** — worst 37 km in about 385,000.
- **Moon's lit percentage** — median 0.36 percentage points off JPL, worst 0.91.
- **Planet brightness** — Jupiter 0.007 mag, Uranus 0.018, Mars 0.115, Neptune 0.130,
  Venus 0.225, Saturn 0.293, **Mercury 0.700**.
- **Constellation assignment** — the Yale catalogue labels 2,785 of its stars with a designation
  that names a constellation. This app's own calculation agrees with **2,785 of 2,785**.

### What is deliberately not right

Said here rather than discovered later:

- **Saturn's brightness** has no ring term. Its rings change its magnitude by up to 0.8 depending
  on how open they are to us, and modelling that needs Saturn's pole orientation. Measured error
  without it: 0.29 magnitudes.
- **Mercury's brightness** is the weakest figure in the app, off by up to 0.7 magnitudes — a
  factor of two in the lux the energy screen quotes. Its phase polynomial is only valid between
  about 2° and 170° of phase angle and Mercury spends much of its time near those limits. The
  energy screen says so on screen.
- **Dates are limited to 1800–2050.** The orbital elements were fitted over that interval and
  JPL states they are not valid outside it, so the app throws rather than extrapolating. An app
  that quietly guesses is an app that lies on its 2051st birthday.
- **Nutation is truncated** to its four largest terms, good to about 0.5″ — an order of magnitude
  below the best body in the table.
- **No atmospheric refraction.** Near the horizon this lifts a body by up to about half a degree.
  Not modelled, because it depends on air temperature and pressure that the app does not know.

### About the energy screen

The app reports **light**, measured in lux, because light is energy and it is the one thing a
planet genuinely delivers to a person. Jupiter really does put more photons on your face than
Mars, or sometimes fewer, and which one wins tonight is a fact that changes.

It does **not** report an influence, and it says so on the screen. The light from the brightest
planet is millions of times weaker than moonlight, and a planet's gravitational pull on you is
smaller than that of the person standing next to you. The numbers are there because they are
true, not because they mean anything about your week. The zodiac sign is shown as what it is — a
tradition, computed exactly — alongside where the Sun actually is.

---

## Build and run

### 1. The star catalogue

Not committed: it is reproducible, and a binary in git means reviewing a binary diff.

```bash
py -3.12 data/sources.py          # fetch the three source catalogues
py -3.12 data/build_catalogue.py  # build app/assets/starmap.db and stars.json
```

No third-party Python packages. Measured: `urllib` reaches all three sources over TLS without
`certifi` on a stock Windows Python 3.12.

That writes 9,096 stars, 341 IAU-approved proper names, the 88 constellations and the 357 IAU
boundary bands.

### 2. The app

```bash
cd app
flutter pub get
flutter run -d chrome        # or an attached phone, or an emulator
```

Both shipping targets have been built on Windows:

| Build | Size |
|---|---|
| `flutter build apk --release --split-per-abi` arm64-v8a | **15.6 MB** |
| the same, armeabi-v7a | 13.0 MB |
| the same, x86_64 | 17.0 MB |
| `flutter build apk --debug` | 152 MB — every architecture plus debug symbols, which is why a debug size says nothing about what a user downloads |
| `flutter build web --release` | 2.0 MB of app code, plus the 454 KB catalogue |

Built and tested with **Flutter 3.47.6 / Dart 3.13.5**. Android needs the Android SDK with
`compileSdk 36` and **JDK 17** — Flutter's Gradle plugin does not accept JDK 25.

Building for iOS needs a Mac with Xcode. The code is iOS-ready and the `Info.plist` carries the
location usage string, but it cannot be compiled or tested on Windows.

### 3. Tests

```bash
py -3.12 -m unittest discover -s data/tests -t data    # 11 tests: the catalogue build
cd app && flutter test                                  # 28 tests: the engine, the online path,
                                                        #           and every screen
```

The online path is tested with **no network at all**: the parser against a real Horizons reply
committed byte for byte, and the observer correction against NASA's own topocentric figures.

The accuracy tests print the error tables above rather than only asserting a threshold, so the
headroom is visible instead of hidden.

---

## How it is put together

```
data/                     Python, build time only. Never ships, never runs on the phone.
  sources.py              fetch the three catalogues, with provenance for each
  precession.py           J2000 -> B1875, so stars land in the right constellation
  constellation.py        the IAU boundary walk (Roman 1987)
  build_catalogue.py      -> app/assets/starmap.db  and  app/assets/stars.json
  make_fixtures.py        -> app/test/fixtures/horizons.json, straight from NASA
  constellations.csv      the 88 Latin names, checked against the boundary table by the build

app/lib/net/
  horizons.dart           the one service this app talks to, and what it refuses to send

app/lib/sky/              the astronomy. Pure Dart, no UI, no I/O, no network.
  julian.dart             time scales and sidereal time
  precession, nutation    frames: J2000, mean of date, true of date
  coordinates.dart        ecliptic -> equatorial -> your horizon
  planets.dart            JPL Keplerian elements
  moon.dart               ELP2000-82, truncated
  sun.dart  phase.dart    the Sun, and the phase and full-moon search
  observer.dart           where you stand, and the parallax that causes
  brightness.dart         magnitude -> lux
  zodiac.dart             both answers, labelled
  ephemeris.dart          which source a position came from, and how to say so
  sky_now.dart            one call every screen reads from - with or without a reference

app/lib/ui/               four screens, one theme
```

The split that matters: **nothing in `ui/` does astronomy**, and nothing in `sky/` knows what a
widget is. One function computes the sky; all four screens read the same result, so no two
screens can disagree about where Jupiter is.

### Why a JSON asset as well as a SQLite file

`starmap.db` is the canonical artefact — it carries the boundary table, the provenance and the
foreign keys, and it is what the Python tests assert against. But reading SQLite from Flutter
needs a native plugin, and native plugins do not work on the web. So the build also writes
`stars.json`: the same data, in a form every platform reads with no dependency at all.

---

## Where the data comes from

| Source | What for | Licence |
|---|---|---|
| [Yale Bright Star Catalogue, 5th rev.](https://vizier.cds.unistra.fr/viz-bin/asu-tsv?-source=V/50) (Hoffleit & Warren 1991, via VizieR) | 9,110 stars to magnitude ~6.5 — the naked-eye sky | CDS/VizieR, free with attribution |
| [IAU Catalog of Star Names](https://www.pas.rochester.edu/~emamajek/WGSN/IAU-CSN.txt) (WGSN) | the only officially approved star names | CC BY 4.0 |
| [Constellation Boundary Data](https://vizier.cds.unistra.fr/viz-bin/asu-tsv?-source=VI/42) (Davenhall & Leggett 1989, via VizieR) | the IAU constellation boundaries | CDS/VizieR, free with attribution |
| [Approximate Positions of the Major Planets](https://ssd.jpl.nasa.gov/planets/approx_pos.html) (NASA/JPL) | planetary orbital elements | public domain |
| [JPL Horizons](https://ssd.jpl.nasa.gov/api/horizons.api) | the reference positions every accuracy test is measured against | public domain |
| Meeus, *Astronomical Algorithms* | the ELP2000-82 lunar series and the nutation terms | — |
| [Spectral](https://fonts.google.com/specimen/Spectral) (Production Type) | the typeface | SIL OFL 1.1 |

8,755 of the 9,096 stars have **no** proper name, and the app leaves them nameless rather than
giving them a popular one. It shows the catalogue designation instead.

---

## Before this can go in a store

The app works and is measured. These are the things that are actually still in the way, so none
of them is a surprise later.

**Android**

- **A signing key.** Release builds are currently signed with Flutter's debug keystore, which
  Google Play rejects - every Flutter project on earth shares that key. One `keytool` command
  creates an upload key; `app/android/app/build.gradle.kts` says exactly what to run and what
  never to commit. Losing that key means losing the ability to update the app, so it needs a
  backup somewhere safe.
- **An app icon.** Still the stock Flutter icon.

**iOS**

- **A Mac with Xcode.** Not a preference - iOS binaries cannot be built on Windows. The code and
  the `Info.plist` are ready, and nothing here has been compiled or tested on iOS, which is why
  this README makes no claim that it works there.
- **An Apple Developer account**, which is a paid yearly membership.

**Both**

- **A privacy declaration**, which is still simple and worth keeping that way. The app collects
  nothing and stores nothing. It asks for coarse location and uses it on the device. It makes one
  kind of outbound request, to `ssd.jpl.nasa.gov`, carrying a body code and a timestamp - no
  identifier, no location, nothing about the person. Both stores ask whether data is "linked to
  the user"; here nothing is sent that could be. That stays true only as long as nobody adds
  analytics or a crash reporter.
- **Screenshots and a listing**, which need the icon first.

One thing worth deciding early: the app currently speaks English only.

---

## Licence

MIT. See [LICENSE](LICENSE).

---

## The brief, as written

The original brief for this project, kept verbatim because it is the specification and the rules
in it still apply:

> This is an tiny app that can cure your curiosity. - It can show you which stars are above you
> based on your location.
>
> you can see your star sign etc you can see what energy is higher up know it needs to follow and
> give you dates of full moon etc it needs to be fun te look at for 2 minutes it needs to be
> something people can look at and see everything about the stars signs and energy etc by energy i
> mean has jupiter more energy or has mars more energy that can be felt by humans succes
>
> dont overengineer, dont overcomplicate, dont put ai slop, it needs toi be facts, it needs to be
> good
>
> workflow : build test (debug) run test (debug) push
>
> you need to be precise with everything.
>
> frontend for android = flutter for ios its swift and flutter
> backend you can use sql for data and you can use python and js maybe c if needed SUCCES

Two notes on how that brief was read, so the reasoning is on the record:

**"energy ... that can be felt by humans"** is answered with light, measured in lux, rather than
with astrology — see [About the energy screen](#about-the-energy-screen). The brief also says
*"it needs to be facts"*, and those two requirements only fit together one way.

**"backend you can use sql for data and you can use python"** is honoured as a build-time
pipeline rather than a server. SQLite is the data format and Python builds it; nothing is hosted,
because the sky is computable from a date, a position and a static catalogue, and a server would
add a failure mode in exchange for nothing.
