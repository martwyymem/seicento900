## Per-track settings (the JS TRACK_CONFIG). The centreline and elevation come from data/tracks/<key>.json,
## generated from OpenStreetMap by tools/build_tracks.py. Edit data/tracks/<key>.tres in the Inspector.
## Distances are metres along the OSM chain (start_offset, corners) or relative to the start line (pit values).
class_name TrackDef
extends Resource

@export var key := ""
@export var display_name := ""
@export var short_name := ""
@export var width := 12.0
@export var start_offset := 0.0 ## where the start line sits along the OSM chain

@export_group("Pit lane")
@export var pit_entry := -400.0
@export var pit_exit := 300.0
@export var pit_ramp := 70.0 ## length of the blend between the track and the lane at each end
@export var pit_offset := 14.0 ## lane centre from the track centre; > 0 puts the pits on the right
@export var box_start := -200.0
@export var box_spacing := 12.0

@export_group("Run-off and barriers")
@export var runoff := 8.0 ## metres of run-off beyond the track edge
@export var runoff_color := Color(0.4, 0.55, 0.3)
@export_enum("grass", "gravel", "asphalt") var runoff_surface := "grass"
@export_enum("armco", "tyres", "armco+fence", "safer") var barrier := "armco"
@export_range(0.0, 35.0, 0.1, "suffix:°") var banking := 0.0 ## banking in the turns; the outside edge is higher

@export_group("Scenery")
@export_enum("forest", "city", "oval") var theme := "forest"
@export var tree_density := 1.0
@export var tree_patch := 0.3 ## how clumped the trees are
@export var tree_conifer := 0.5 ## share of conifers
@export var terrain_fine := 8.0 ## terrain grid spacing near the track (m)
@export var grandstands := true
@export var stands := Vector2(-330, 250) ## grandstand span relative to the start line
@export var stand_tiers := 5
@export var sea := false
@export var floodlight_spacing := 180.0 ## metres between floodlight masts round the lap; 0 for none (the city has street lamps)

@export_group("Names")
@export var osm_names := false ## use the section names from OpenStreetMap
@export var corners: Array[CornerName] = []
