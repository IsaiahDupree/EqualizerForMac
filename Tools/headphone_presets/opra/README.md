# OPRA Beats preset data

These files contain published **data**, selected from the
[Open Profiles for Revealing Audio (OPRA) project](https://github.com/opra-project/OPRA)
at commit `0b88ecd4e2bef7cf69fd5d50f1d06fb586c10865`, reviewed November 3, 2026.
OPRA collects headphone models and EQ profiles from community creators. No
external app implementation is included.

The preset creators are **oratory1990** and **AutoEQ**. AutoEQ's measurement
source is Rtings for the two added AutoEQ curves. Each raw JSON file retains
its author, target/details, bands and preamp. `manifest.json` pins every raw
file by SHA-256 and links directly to its original revision.

| Model | Additional published correction |
| --- | --- |
| Beats EP | oratory1990 · Harman Target |
| Beats Fit Pro | oratory1990 · Harman Target |
| Beats Powerbeats Pro | oratory1990 · Harman Target; USound Target |
| Beats Pro | oratory1990 · Harman Target |
| Beats Solo Pro | oratory1990 · Harman Target |
| Beats Solo3 Wireless (2018) | AutoEQ · measured by Rtings |
| Beats Solo3 (wireless, 2019) | AutoEQ · measured by Rtings |
| Beats Studio Buds | oratory1990 · Harman Target; USound Target |
| Beats Studio3 Wireless | oratory1990 · Harman Target |

The 65 OPRA Beats records include aliases/duplicate curves. Selection compared
the actual filter coefficients' inputs and preamps against the existing Beats
catalog and excluded duplicate USound/oratory1990 target aliases. Eleven
distinct corrections were added. This is not eleven new headphone generations.

## Data license and attribution

The data in this directory, the selected data in
[`OPRA-Beats.json`](../../../Sources/SonanceEQ/Resources/OPRA-Beats.json), and
the corresponding converted database entries are distributed under
[Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/).
The full upstream license is bundled in
[`OPRA-LICENSE.txt`](../../../Sources/SonanceEQ/Resources/OPRA-LICENSE.txt).
Retain the preset creator credits, OPRA credit, source links and this notice
when redistributing or adapting this data. This data notice does not relicense
Sonance EQ's independently authored application code.

The app credits the creator and target in each preset row, links the exact
published file from its context menu, and displays OPRA's logo, description,
repository and data links in the library. The data link and this public source
remain accessible without a Pro purchase.

## Conversion and numerical validation

`build_autoeq_db.py` converts `peak_dip`, `low_shelf` and `high_shelf` to the
app's existing peaking/shelf types. Frequencies, gains and Q values are retained.
The source does not specify a measurement rig or ANC/transparency condition
for these selections; do not invent one or promise unit-specific correction.

Native response checks at 44.1, 48, 96 and 192 kHz found tiny positive peaks
after two published preamps. The catalog therefore uses -5.6 dB instead of
-5.5 dB for Solo3 Wireless (2018), and -2.3 dB instead of -2.2 dB for Studio
Buds Harman. These conservative 0.1 dB reductions are recorded separately in
the manifest and bundled data. Original source files stay unchanged.

The native tests compare every filter to the bundled published input, apply
each through `AppState`, and verify finite response, stable sections and
nonpositive magnitude after preamp across the tested frequency grid. Python
checks pin the raw inputs and licenses and preserve every 1.0.7 row. These
checks do not establish physical audibility, headphone fit or hardware testing.
