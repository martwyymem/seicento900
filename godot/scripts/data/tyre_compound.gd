## One tyre compound (data/tyres/<key>.tres): its colour on the HUD, grip and tread life. Edit in the Inspector.
class_name TyreCompound
extends Resource

@export var key := "M" ## S, M, H or W (Tyres.KEYS)
@export var display_name := "Medium"
@export var color := Color("#ffd23b")
@export var grip := 1.0 ## grip multiplier; Medium is 1.0
@export var life := 32000.0 ## metres to wear the tread away at nominal load
