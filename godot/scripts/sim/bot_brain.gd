## Per-bot learning-AI state (the JS car.brain), owned by Brain.
class_name BotBrain
extends RefCounted

var e := PackedFloat64Array() ## learned pace per section (fraction of the grip limit)
var e0 := PackedFloat64Array()
var talent := 1.0
var cap := 1.0
var floor_ := 0.9
var bin := -1
var dirty := false
var mind := "race" ## race | attack | defend | manage
var think_t := 0.0
var zone := -1
var boost_t := 0.0
var att = null ## {id, t, d0, side, judged, switched} or null
var covering := false
var last_said := -99.0
var said := {}
var copied := 0
var copy_gain := 0.0
var mistakes := 0
