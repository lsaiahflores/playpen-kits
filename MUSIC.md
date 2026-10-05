# MUSIC — you compose, Playpen produces the sound

Do **not** synthesize melodies in code (no `sin()` beeps). Playpen renders MIDI with real
instruments (a General MIDI SoundFont) into mastered OGG files. No AI audio models.

## One command (recommended for a first pass)

```
playpen-music auto --track area1 --title "Bay Theme"
```

Composes an ORIGINAL song from the look pack's mood / key / scale / tempo / instruments
(`playpen/lookpack.json` → `audio`), renders it, and also renders the stingers
(`victory`, `checkpoint`, `go`, `game_over`, `pickup`) and a musical pickup note in the same key.

## Writing your own (when the design calls for something specific)

```
playpen-music compose --mood adventurous --key E --scale lydian --bpm 104 --bars 8 --out music_src/area1/song.json
# edit the notes / instruments / structure in song.json, then:
playpen-music render music_src/area1/song.json --track area1
```

`song.json` shape (all times in **beats**, 4/4):

```json
{ "title": "...", "key": "C", "scale": "major", "bpm": 112, "loopBars": 8, "introBars": 2,
  "intro": [ TRACK ],
  "loop":      { "base": [TRACK], "rhythm": [TRACK], "melody": [TRACK], "intensity": [TRACK] },
  "variation": { "base": [TRACK], "rhythm": [TRACK], "melody": [TRACK], "intensity": [TRACK] } }
TRACK = { "name": "lead", "channel": 3, "program": 73, "volume": 112, "pan": 64,
          "notes": [ { "t": 0, "d": 1, "n": 76, "v": 96 } ] }       // start beat, length, MIDI note, velocity
```

* **Stems** are what the game mixes: `base` (bass + harmony), `rhythm` (drums + comping),
  `melody` (lead + counter), `intensity` (the extra layer for danger / boss).
* Each stem must sound good alone **and** together. Channel 9 = drums (GM percussion); other
  channels need distinct numbers within one section. `program` = General MIDI number (0-127).
* Structure: **intro → loop → variation**, seamless loop points (the tail of the last bar rings into the first).
* **ORIGINAL melodies only.** Never recreate a known song or theme. (IP rule.)

## What you get (and how the game uses it)

```
audio/music/area1/{base,rhythm,melody,intensity}.ogg  intro.ogg  track.json
audio/music/area1_b/…                                (the variation)
audio/stingers/*.ogg   audio/sfx/pickup.ogg
music_src/area1/{song.json,loop.mid,variation.mid,intro.mid}   <- kept: edit and re-render any time
```

```gdscript
PNAudio.play_track("area1")            # crossfades from whatever was playing; plays the intro first
PNAudio.set_state("explore")           # explore | danger | underwater | indoor | boss | menu
PNAudio.play_track("area1_b")          # switch to the variation
PNAudio.stinger("victory")             # checkpoint / go / game_over / pickup
PNAudio.pickup(combo)                  # plays IN THE MUSIC'S KEY, climbs the scale on combos
PNAudio.set_space("cave")              # reverb: open / indoor / cave / underwater
```

Mix: buses Master / Music / SFX / Ambience / UI, a compressor + limiter on Master, music ducks
under important SFX and menus, volume sliders in Settings. Loudness is normalized (≈ -16 LUFS).

Until a track is rendered the kit plays a short built-in fallback loop for the look pack's mood —
never the final sound. Per area, make a track (`--track area2`) and call `PNAudio.play_track("area2")`
when the player enters it.
