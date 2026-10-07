<p align="center"><img src=".github/logo.png" alt="Nameplate Distance logo" width="160"></p>

# Nameplate Distance

An addon for WoW Forever (the `_classic_beta_` client, 1.60.x) that shows on
each nameplate how far away the unit is, colored by distance.

- **Distance on every nameplate.** The game only tells addons whether a unit
  is in range of a spell, an item or an interaction, so the distance is a
  range such as `20-25 yd`, bracketed with your own spells (talents
  included), a few items and the interaction distances. Party and raid
  members get an exact number.
- **Real melee range for your target.** Melee reach is not a fixed 5 yards:
  it grows with the size of both models and while both of you are moving.
  For your target, the addon reads the range of the melee abilities on your
  action bars, the same answer that turns their buttons red. Some buttons,
  such as Raptor Strike's (it only changes your next swing), say "in range"
  at almost any distance, so when your melee buttons disagree, "out of range"
  wins, and none is believed past 8 yards. Other units use a fixed 5 yard
  check.
- **Colors by class.** Each character gets color rows set up from its class
  and from the distances its range checks can tell apart, so the numbers on
  the nameplates match the rows:
  - Hunters: green in melee range, red in the dead zone, green in the middle
    of the shooting range, red past it, grey past Hunter's Mark.
  - Warriors, rogues, and druids in cat or bear form: green in melee range;
    with a charge, red up to its minimum range and light green within its
    range; then yellow to orange up to their longest ability, red past it.
    Druids keep separate rows for their own form, cat form and bear form.
  - Other classes: green up close to red past their longest spell.

  The rows follow new spells and talents until you edit one. **Adjust to
  class & talents** sets them up again.
- **Display options.** Where the text sits on the health bar (nine points,
  inside or next to it, with offsets), font size and outline, the format
  (the color rows' ranges, `20-25`, `25` or `~23`), the distance color on the
  text and on the unit's name, enemies and friendly units, only your target,
  hiding "more than" distances, and how often it updates.
- **Every client language.** The texts are in English, German, Spanish (EU
  and Latin America), French, Italian, Korean, Portuguese (Brazil, also used
  by Portugal's client), Russian and Chinese (simplified and traditional).
  The distance unit follows the client: yd, m, м, 미터, 码 or 碼.

## Installing

1. Copy the `NameplateDistance` folder into
   `World of Warcraft\_classic_beta_\Interface\AddOns\`.
2. Open the options with `/npd`, or from the game menu: Options > AddOns >
   Nameplate Distance.

For your target's real melee range, keep a melee ability on any action bar,
even a hidden one. After each login the addon starts using a button once it
has seen it say both "in range" and "out of range", which happens the first
time you walk up to a target.

The text, position and display options are shared by all the characters of
your account; the color rows belong to each character. The game saves them
in `NameplateDistanceDB`.

## Commands

| Command | What it does |
|---|---|
| `/npd` | Open the options |
| `/npd check` | The range checks that answer for your target and what they say, in a window you can copy |
| `/npd melee` | What each melee button on your bars says about your target, in a window you can copy (`/npd melee log` records the range events until you run it again) |
| `/npd reset` | Restore the default settings |

`/nameplatedistance` works as well as `/npd`.

## How the distance is measured

- **Range checks.** Spells from your spellbook, items with a known range and
  the interaction distances (8 and 28 yards; a little less for Tauren and
  Undead). An item counts once the client has answered for it, and is
  remembered from then on. Spells cast on your pet (Mend Pet, Dismiss Pet...)
  answer for the pet, whatever unit they are asked about, so they are left
  out.
- **Spells that go quiet.** On WoW Forever a spell answers nothing, instead of
  "out of range", once the unit is out of its range. A spell that answered
  before for the same unit is therefore read as out of range.
- **Combat.** Items and interactions cannot be used in combat on units you
  cannot attack, so friendly ranges get coarser during a fight.

## Files

| File | Purpose |
|---|---|
| `Locales\` | Translations, one file per language; the English text is the key |
| `Core.lua` | Settings, shared helpers, startup, slash commands |
| `Range.lua` | Range checks, the target's melee reach, `/npd check` and `/npd melee` |
| `Colors.lua` | The color rows of each class, character and druid form |
| `Nameplates.lua` | The distance text and the name color on Blizzard's nameplates |
| `Options.lua` | The settings pages |
| `Tests\` | Offline tests (not loaded by the game) |
| `.github\logo.png` | The project logo (not part of the addon) |
| `CHANGELOG.md` | Release notes, shown on CurseForge for each file |
| `.pkgmeta` | How CurseForge packages a release |

## Tests

The tests run the real addon files, loaded in the order of the TOC, against
a strict stand-in for the WoW Forever API: units at known distances, a
virtual clock, nameplates, action bars and the settings pages. They need a
Lua 5.1 interpreter, the game's Lua:

```
lua5.1 Tests\run.lua [path to NameplateDistance]
```

The path defaults to the folder that holds `Tests`. The tests walk units of
every kind away from the player and check that each nameplate shows its own
range in the right color; they cover the hunter, warrior, rogue, druid (in
each form), mage and shaman rows, the target's melee reach, the options
pages, the saved settings, secret values, and every client language, which
must translate exactly the texts the code uses, with the same placeholders.
They also fail if the addon sets a global other than its saved settings and
slash commands.

## Releasing

CurseForge packages every tagged commit pushed to this repository.

1. Raise `## Version` in `NameplateDistance.toc` and add that version's entry
   at the top of `CHANGELOG.md`. The tests check that both match.
2. Commit, tag the commit `v<version>` and push the tag:
   `git push origin v<version>`. A tag containing `beta` or `alpha` makes a
   beta or alpha file instead of a release.
3. CurseForge builds the zip as `.pkgmeta` says: the `NameplateDistance`
   folder without the tests, with `CHANGELOG.md` as the file's changelog.

## License

MIT, see [LICENSE](LICENSE).
