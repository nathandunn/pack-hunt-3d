extends RefCounted
##
## The palette. Every colour the app draws lives here and nowhere else.
##
## The rule this file exists to enforce is legibility, not realism. A wolf is
## grey-brown and a deadfall is grey-brown and a summer field is dark green, and
## putting all three on a phone screen in daylight produced exactly what you
## would expect: a dark thing on a dark thing. Realism loses. Every element that
## a viewer has to tell apart is now checked against the ground it sits on at
## **WCAG 3:1 or better** — the bar for non-text graphical objects — and
## `scripts/tests.gd` asserts it, so the check is not a one-off.
##
## The separations, measured against GROUND:
##
##   wolf        light grey        8.28 : 1
##   deer        light red-brown   4.19 : 1
##   deadfall    warm mid-tone     4.24 : 1   top edge 6.47 : 1
##   goal strip  bright green      5.91 : 1
##
## Wolf against deer is 1.98 : 1 in luminance, which is deliberate and is not a
## failure: the two species are separated on **hue** — neutral grey against warm
## tan — which survives both daylight and the common forms of colour blindness,
## where a luminance-only split does not. What must not happen is either of them
## sinking into the field, and that is what the 3:1 bar above pins.
##
## Fatigue does not darken the coat any more. It used to multiply the tint by
## up to 0.55, which took a spent deer from 4.19 : 1 down to 2.31 : 1 — the
## animal became least visible at exactly the moment the run gets interesting.
## It now interpolates toward a *spent* colour of the same lightness and less
## saturation, which reads as "used up" and stays above the bar (4.45 : 1).
##

## Field and sky.
const GROUND := Color("#34412b")          ## muted green, a step lighter than the old #1a2015
const SKY := Color("#202a1b")
const FOG := Color("#2c3826")

## The strip on the left edge the deer is running for.
const GOAL := Color("#8ed07a")
const GOAL_GLOW := Color("#4e8c42")

## Deadfall. A warm mid-tone against a green field, with a lit top edge so the
## slab reads as having a height rather than as a stain on the grass.
const OBSTACLE := Color("#c89a55")
const OBSTACLE_TOP := Color("#e3c489")
const OBSTACLE_TRUNK := Color("#a8793d")

## Animals.
const WOLF := Color("#dfe2db")
const WOLF_SPENT := Color("#a9b0ab")
const DEER := Color("#dd8f4e")
const DEER_SPENT := Color("#c2a07e")
const DEAD := Color("#d96a58")

## Lighting. Warm key, cool-green fill; the ambient is what keeps a face that
## is turned away from the sun off the floor of the range.
const SUN_LIGHT := Color("#fff5db")
const AMBIENT := Color("#6c7a63")

## UI chrome.
const UI_TEXT := Color("#dbe2d4")
const UI_MUTED := Color("#9aa693")
const UI_PANEL := Color("#1b2317")
const UI_BUTTON := Color("#2a3423")
const UI_BUTTON_HOVER := Color("#3c4a32")
const UI_BUTTON_PRESSED := Color("#c89a55")
const UI_BORDER := Color(1, 1, 1, 0.16)
const UI_BORDER_SOFT := Color(1, 1, 1, 0.12)
const UI_SCRIM := Color(0, 0, 0, 0.45)


##
## The coat of an animal at `fatigue` in 0..1 — a lerp toward the spent tone,
## never a darkening. See the note at the top of the file.
##
static func coat(base: Color, spent: Color, fatigue: float) -> Color:
	return base.lerp(spent, clampf(fatigue, 0.0, 1.0))


## sRGB -> relative luminance, WCAG 2.x.
static func luminance(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	var w := [0.2126, 0.7152, 0.0722]
	var l := 0.0
	for i in range(3):
		var v: float = ch[i]
		l += w[i] * (v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return l


## WCAG contrast ratio between two colours, 1.0 .. 21.0.
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)
