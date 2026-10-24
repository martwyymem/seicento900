#!/usr/bin/env python3
"""
Generate authentic, street-accurate City and Regional Track Splines, 3D Surroundings & Land Maps for Seicento (Pillar 3).
Constructs realistic urban and country racing circuits modeled on real city street layouts:
1. Tokyo C1 Expressway (Shuto C1 elevated viaducts, Yaesu tunnel, Hamazakibashi & Edobashi JCTs, canals)
2. Bielsko-Biała Szyndzielnia (FSM factory straight, 3 Maja, Sułkowski Castle viaduct, mountain climb to Szyndzielnia)
3. Kraków Royal Ring (Authentic Planty ring road encircling Wawel Castle, Basztowa, Barbakan, Westerplatte, Wisła river)
4. Oświęcim Riverfront (Bulwary nad Sołą, historic Piast Castle, Rynek, Most Piastowski over Soła River)
5. Pszczyna Castle Grounds (Rynek cobblestones, Brama Wybrańców, Pałac Pszczyński, English Castle Park, Swan Lake)
6. Brzeszcze Industrial Sprint (KWK Szyb Andrzej headframe, Dworcowa, railway crossing chicane, mining colony)
7. Wilamowice Country Loop (Historic Rynek, Mielnicki ridge rollercoaster, rolling Silesian foothills, fishing ponds)

Outputs for each track:
- godot/data/tracks/<key>.json       Track spline, step, length, elevation profile, 3D DEM grid
- godot/data/tracks/<key>.tres       Godot TrackDef resource
- godot/data/tracks/<key>_env.json   Full 3D surroundings: buildings, water, landmarks, trees, stands, bridges
- godot/data/tracks/<key>_land.png   Land map texture (R: paved/streets/sidewalks, G: grass/lawns, B: cobblestones/bare, A: forest)
"""

import json
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

def fillet_path(vertices, corner_radii, default_radius=18.0, num_arc_pts=16):
    """
    Construct a realistic urban road polygon with filleted corner arcs between straight street segments.
    vertices: list of (x, y, z) intersection points.
    corner_radii: list or dict of corner radii (in metres) at each vertex.
    """
    V = [np.array(v, dtype=float) for v in vertices]
    N = len(V)
    dense_pts = []
    
    for i in range(N):
        im1 = (i - 1 + N) % N
        ip1 = (i + 1) % N
        
        P_prev = V[im1]
        P_curr = V[i]
        P_next = V[ip1]
        
        # 2D direction vectors
        d1 = P_curr[:2] - P_prev[:2]
        d2 = P_next[:2] - P_curr[:2]
        l1 = np.hypot(d1[0], d1[1])
        l2 = np.hypot(d2[0], d2[1])
        if l1 < 1e-4 or l2 < 1e-4:
            dense_pts.append(P_curr)
            continue
            
        u1 = d1 / l1
        u2 = d2 / l2
        
        # Turn angle
        dot = np.clip(np.dot(-u1, u2), -1.0, 1.0)
        theta = math.acos(dot)
        
        radius = corner_radii.get(i, default_radius) if isinstance(corner_radii, dict) else (corner_radii[i] if i < len(corner_radii) else default_radius)
        tan_half = math.tan(theta / 2.0) if abs(math.sin(theta / 2.0)) > 1e-4 else 1e-4
        t_dist = radius / tan_half
        
        # Cap tangent distance to half of segment lengths so corners do not overlap
        t_dist = min(t_dist, l1 * 0.45, l2 * 0.45)
        radius = t_dist * tan_half
        
        T1_2d = P_curr[:2] - u1 * t_dist
        T2_2d = P_curr[:2] + u2 * t_dist
        
        # Elevation interpolation
        z_t1 = P_curr[2] - (P_curr[2] - P_prev[2]) * (t_dist / l1)
        z_t2 = P_curr[2] + (P_next[2] - P_curr[2]) * (t_dist / l2)
        
        # Corner center
        n1 = np.array([-u1[1], u1[0]])
        cross_z = u1[0] * u2[1] - u1[1] * u2[0]
        if cross_z < 0: # right turn
            n1 = -n1
            
        center = T1_2d + n1 * radius
        
        # Sample circular arc between T1 and T2
        v_start = T1_2d - center
        v_end = T2_2d - center
        a_start = math.atan2(v_start[1], v_start[0])
        a_end = math.atan2(v_end[1], v_end[0])
        
        diff_a = (a_end - a_start + math.pi) % (2.0 * math.pi) - math.pi
        if cross_z > 0 and diff_a < 0:
            diff_a += 2.0 * math.pi
        elif cross_z < 0 and diff_a > 0:
            diff_a -= 2.0 * math.pi
            
        n_pts = max(4, int(num_arc_pts * abs(diff_a) / (math.pi / 2.0)))
        for k in range(n_pts + 1):
            t = k / float(n_pts)
            ang = a_start + diff_a * t
            p_arc_2d = center + np.array([math.cos(ang), math.sin(ang)]) * radius
            z_arc = (1.0 - t) * z_t1 + t * z_t2
            dense_pts.append(np.array([p_arc_2d[0], p_arc_2d[1], z_arc]))
            
    # Resample dense polyline evenly at step = 2.0m with clean periodic closure
    filtered = [dense_pts[0]]
    for p in dense_pts[1:]:
        if np.hypot(p[0] - filtered[-1][0], p[1] - filtered[-1][1]) > 1e-4:
            filtered.append(p)
    if np.hypot(filtered[-1][0] - filtered[0][0], filtered[-1][1] - filtered[0][1]) < 1e-4:
        filtered.pop()

    closed = np.vstack([filtered, filtered[0:1]])
    diffs = closed[1:] - closed[:-1]
    dists = np.hypot(diffs[:, 0], diffs[:, 1])
    cum_dist = np.zeros(len(closed))
    cum_dist[1:] = np.cumsum(dists)
    total_L = float(cum_dist[-1])
    n_samples = int(round(total_L / 2.0))
    actual_step = total_L / n_samples
    target_s = np.arange(n_samples) * actual_step
    resampled_x = np.interp(target_s, cum_dist, closed[:, 0])
    resampled_y = np.interp(target_s, cum_dist, closed[:, 1])
    resampled_z = np.interp(target_s, cum_dist, closed[:, 2])

    return n_samples, actual_step, total_L, resampled_x, resampled_y, resampled_z


def generate_dem_grid(resampled_x, resampled_y, resampled_z, grid_step=25.0, padding=350.0):
    min_x = float(np.min(resampled_x)) - padding
    max_x = float(np.max(resampled_x)) + padding
    min_y = float(np.min(resampled_y)) - padding
    max_y = float(np.max(resampled_y)) + padding
    
    nx = int(math.ceil((max_x - min_x) / grid_step)) + 1
    ny = int(math.ceil((max_y - min_y) / grid_step)) + 1
    
    sub_x = resampled_x[::6]
    sub_y = resampled_y[::6]
    sub_z = resampled_z[::6]
    
    grid_h = []
    for iy in range(ny):
        gy = min_y + iy * grid_step
        for ix in range(nx):
            gx = min_x + ix * grid_step
            d2 = (sub_x - gx)**2 + (sub_y - gy)**2
            nearest_idx = np.argmin(d2)
            dist = math.sqrt(d2[nearest_idx])
            track_h = sub_z[nearest_idx]
            
            undulation = 3.5 * math.sin(gx * 0.007 + gy * 0.005) * math.cos(gy * 0.008 - gx * 0.004)
            blend = 1.0 - math.exp(-dist / 65.0)
            h_val = round(track_h - 0.25 * (1.0 - blend) + undulation * blend, 2)
            grid_h.append(h_val)
            
    return {
        "x0": round(min_x, 2),
        "y0": round(min_y, 2),
        "step": grid_step,
        "nx": nx,
        "ny": ny,
        "h": grid_h
    }

# ----------------- TRUE CITY STREET CONFIGURATIONS -----------------

STREET_TRACKS = [
    # 1. KRAKÓW: The Planty Ring around Wawel Castle and the Old Town (UNESCO World Heritage)
    {
        "key": "krakow",
        "display_name": "Kraków Royal Ring",
        "short_name": "Kraków",
        "width": 7.5,
        "theme": "city",
        "barrier": "armco",
        "runoff": 3.0,
        "runoff_surface": "asphalt",
        "runoff_paved": 1.2,
        "kerb_style": "red_white",
        "kerb_width": 1.0,
        "tree_density": 0.45,
        "tree_patch": 0.6,
        "tree_conifer": 0.15,
        "grandstands": True,
        "stand_tiers": 3,
        "pit_entry": -240.0,
        "pit_exit": 220.0,
        "pit_offset": 8.5,
        "street_nodes": [
            [0.0, 0.0, 219.0],         # 0: ul. Podzamcze (foot of Wawel Castle hill)
            [-180.0, -10.0, 219.5],    # 1: Podzamcze / Straszewskiego corner by Vistula
            [-190.0, -220.0, 220.5],   # 2: ul. Straszewskiego past Filharmonia
            [-195.0, -480.0, 221.0],   # 3: ul. Podwale past Collegium Novum
            [-190.0, -660.0, 221.5],   # 4: Teatr Bagatela Corner (sharp 90° right into Dunajewskiego)
            [20.0, -670.0, 222.0],     # 5: ul. Dunajewskiego past Plac Szczepański
            [260.0, -680.0, 223.0],    # 6: ul. Basztowa transition
            [580.0, -690.0, 223.5],    # 7: Basztowa Boulevard flying past Barbakan & Brama Floriańska
            [740.0, -680.0, 223.0],    # 8: Dworzec Główny / Lubicz Corner (heavy 90° right into Westerplatte)
            [720.0, -380.0, 222.0],    # 9: ul. Westerplatte street canyon
            [700.0, -120.0, 221.0],    # 10: Westerplatte / Poczta Główna corner into Św. Gertrudy
            [540.0, 40.0, 220.0],      # 11: ul. Św. Gertrudy past Hotel Royal
            [320.0, 110.0, 219.5],     # 12: Wawel Bastion Chicane (ul. Św. Idziego)
            [120.0, 40.0, 219.0],      # 13: Beneath Senatorska Tower into Podzamcze
        ],
        "radii": {
            0: 25.0, 1: 30.0, 2: 45.0, 3: 40.0, 4: 18.0, 5: 35.0, 
            6: 30.0, 7: 60.0, 8: 16.0, 9: 40.0, 10: 24.0, 11: 35.0, 12: 22.0, 13: 25.0
        },
        "corners": [
            (0.0, "Podzamcze Wawelskie"),
            (210.0, "Zakręt Filharmonii"),
            (520.0, "Prosta Collegium Novum"),
            (730.0, "Szykana Teatru Bagatela"),
            (980.0, "Dunajewskiego Sweeper"),
            (1280.0, "Basztowa Prosta"),
            (1580.0, "Barbakan Krakowski"),
            (1860.0, "Zakręt Dworcowy"),
            (2140.0, "Aleja Westerplatte"),
            (2420.0, "Gertrudy Parkowa"),
            (2680.0, "Baszta Senatorska Wawelu")
        ],
        "water_polys": [
            # Wisła (Vistula) River curving along the south/west of Wawel Castle
            [-420.0, 140.0, -320.0, 260.0, -120.0, 340.0, 160.0, 380.0, 420.0, 360.0, 
             680.0, 280.0, 840.0, 180.0, 860.0, 120.0, 680.0, 220.0, 400.0, 300.0, 
             140.0, 310.0, -100.0, 280.0, -280.0, 210.0, -380.0, 100.0]
        ],
        "landmarks": [
            ["CastleKeep", 220.0, -40.0, 24.0, 24.0, 0.2, 28.0],   # Wawel Castle Main Keep
            ["CastleTower", 140.0, 20.0, 12.0, 12.0, 0.0, 34.0],   # Senacka Tower
            ["CastleTower", 320.0, -10.0, 10.0, 10.0, 0.5, 30.0],  # Sandomierska Tower
            ["CastleTower", 570.0, -690.0, 14.0, 14.0, 0.0, 22.0], # Barbakan Krakowski
        ],
        "rynek_rect": [150.0, -420.0, 180.0, 180.0], # Rynek Główny w Krakowie
        "building_heights": [16.0, 22.0],
        "building_kind": 1 # Historic townhouses
    },

    # 2. TOKYO: Real Shuto C1 Inner Circular Route with elevated overpasses and Yaesu tunnel
    {
        "key": "tokyo",
        "display_name": "Tokyo C1 Expressway",
        "short_name": "Tokyo C1",
        "width": 7.5,
        "theme": "city",
        "barrier": "armco",
        "runoff": 3.0,
        "runoff_surface": "asphalt",
        "runoff_paved": 1.0,
        "kerb_style": "blue_white",
        "kerb_width": 1.0,
        "tree_density": 0.08,
        "tree_patch": 0.4,
        "tree_conifer": 0.05,
        "grandstands": True,
        "stand_tiers": 4,
        "pit_entry": -280.0,
        "pit_exit": 260.0,
        "pit_offset": 9.2,
        "tunnel_range": [0.55, 0.72], # Yaesu Underground Tunnel
        "street_nodes": [
            [0.0, 0.0, 18.0],          # 0: Ginza Elevated Viaduct
            [220.0, -10.0, 18.0],      # 1: Kyobashi straight
            [440.0, -40.0, 16.5],      # 2: Takaracho curve
            [620.0, -180.0, 15.0],     # 3: Shiodome S-Bends approach
            [660.0, -420.0, 14.0],     # 4: Hamazakibashi JCT (tight multi-level curve over canal)
            [460.0, -640.0, 22.0],     # 5: Shiba Park climb (Tokyo Tower vista)
            [160.0, -740.0, 25.0],     # 6: Ichinohashi JCT viaduct
            [-180.0, -710.0, 24.0],    # 7: Tanimachi JCT interchange
            [-420.0, -580.0, 18.0],    # 8: Kasumigaseki flyover
            [-580.0, -360.0, 12.0],    # 9: Miyakezaka JCT curve (Palace Moat blind corner)
            [-620.0, -120.0, 3.5],     # 10: Dive into Yaesu Tunnel portal
            [-540.0, 120.0, 2.0],      # 11: Yaesu Sub-Level expressway
            [-360.0, 280.0, 2.0],      # 12: Underground Tokyo Station bypass
            [-120.0, 340.0, 8.0],      # 13: Kanda tunnel exit climb
            [120.0, 320.0, 14.5],      # 14: Kanda-bashi skyway
            [340.0, 220.0, 17.5],      # 15: Edobashi JCT triple-tier interchange ramp
            [200.0, 80.0, 18.0],       # 16: Nihonbashi crossover back to Ginza
        ],
        "radii": {
            0: 45.0, 1: 50.0, 2: 35.0, 3: 30.0, 4: 26.0, 5: 35.0, 6: 40.0,
            7: 35.0, 8: 45.0, 9: 28.0, 10: 35.0, 11: 40.0, 12: 45.0, 13: 35.0, 14: 40.0, 15: 25.0, 16: 30.0
        },
        "corners": [
            (0.0, "Ginza Viaduct"),
            (380.0, "Takaracho Sweeper"),
            (720.0, "Hamazakibashi JCT"),
            (1140.0, "Shiba Park Overpass"),
            (1480.0, "Tanimachi S-Curve"),
            (1860.0, "Kasumigaseki Flyover"),
            (2180.0, "Miyakezaka Moat Curve"),
            (2480.0, "Yaesu Tunnel Portal"),
            (2790.0, "Yaesu Sub-Level Straight"),
            (3080.0, "Kanda-bashi Bridge"),
            (3360.0, "Edobashi Multi-Tier JCT")
        ],
        "water_polys": [
            # Hamazakibashi Tokyo Canal
            [600.0, -360.0, 780.0, -390.0, 760.0, -560.0, 580.0, -520.0],
            # Imperial Palace Moat
            [-680.0, -320.0, -520.0, -340.0, -560.0, -480.0, -720.0, -440.0]
        ],
        "landmarks": [
            ["IndyPagoda", 380.0, -680.0, 35.0, 35.0, 0.0, 90.0], # Tokyo Tower representation
        ],
        "building_heights": [28.0, 68.0],
        "building_kind": 1 # Skyscraper & high-rise office blocks
    },

    # 3. BIELSKO-BIAŁA: Historic birthplace of Seicento — FSM Factory, 3 Maja, Castle & Szyndzielnia Mountain Pass
    {
        "key": "bielsko",
        "display_name": "Bielsko-Biała Szyndzielnia",
        "short_name": "Bielsko-Biała",
        "width": 7.0,
        "theme": "city",
        "barrier": "armco",
        "runoff": 3.5,
        "runoff_surface": "asphalt",
        "runoff_paved": 1.0,
        "kerb_style": "yellow_black",
        "kerb_width": 1.1,
        "tree_density": 0.45,
        "tree_patch": 0.7,
        "tree_conifer": 0.6,
        "grandstands": True,
        "stand_tiers": 3,
        "pit_entry": -250.0,
        "pit_exit": 220.0,
        "pit_offset": 8.6,
        "street_nodes": [
            [0.0, 0.0, 320.0],          # 0: ul. Warszawska (Gates of FSM / Fiat factory)
            [40.0, -320.0, 325.0],      # 1: ul. 3 Maja past Dworzec Główny PKP
            [20.0, -560.0, 335.0],      # 2: Zamek Książąt Sułkowskich viaduct into Zamkowa
            [-60.0, -820.0, 345.0],     # 3: ul. Partyzantów straight
            [-220.0, -1080.0, 360.0],   # 4: Rondo gen. Andersa onto al. Armii Krajowej
            [-450.0, -1250.0, 385.0],   # 5: Olszówka climbing pass
            [-680.0, -1350.0, 420.0],   # 6: Steep S-bends approaching Dębowiec
            [-880.0, -1420.0, 458.0],   # 7: Patelnia Szyndzielnia (historic 180° mountain hairpin at 458m)
            [-940.0, -1240.0, 435.0],   # 8: Upper Kolejka descent
            [-860.0, -960.0, 400.0],    # 9: ul. Karpacka winding mountain descent
            [-680.0, -680.0, 370.0],    # 10: Kamienica district sweepers
            [-460.0, -420.0, 345.0],    # 11: ul. Cieszyńska approach
            [-240.0, -200.0, 330.0],    # 12: Rynek w Bielsku (cobblestone Old Market Square)
            [-90.0, -60.0, 322.0],      # 13: ul. Piłsudskiego corner returning to Warszawska
        ],
        "radii": {
            0: 35.0, 1: 30.0, 2: 24.0, 3: 40.0, 4: 35.0, 5: 38.0, 6: 28.0,
            7: 15.0, 8: 25.0, 9: 32.0, 10: 36.0, 11: 30.0, 12: 20.0, 13: 25.0
        },
        "corners": [
            (0.0, "Prosta Fabryczna FSM"),
            (320.0, "Dworzec Główny 3 Maja"),
            (620.0, "Wiadukt Zamku Sułkowskich"),
            (950.0, "Aleja Partyzantów"),
            (1280.0, "Olszówka Hillclimb"),
            (1620.0, "Zakręty pod Dębowcem"),
            (1940.0, "Patelnia Szyndzielnia (458m)"),
            (2250.0, "Zjazd Karpacki"),
            (2580.0, "Szykana Kamienicka"),
            (2820.0, "Rynek Starego Bielska")
        ],
        "landmarks": [
            ["CastleKeep", 30.0, -580.0, 30.0, 22.0, 0.1, 26.0], # Zamek Książąt Sułkowskich
            ["CastleTower", 10.0, -550.0, 8.0, 8.0, 0.0, 32.0]   # Castle Round Tower
        ],
        "rynek_rect": [-240.0, -200.0, 80.0, 80.0],
        "building_heights": [14.0, 24.0],
        "building_kind": 1
    },

    # 4. PSZCZYNA: The Pearl of Upper Silesia — Rynek, Brama Wybrańców, Pałac Pszczyński & English Castle Park
    {
        "key": "pszczyna",
        "display_name": "Pszczyna Castle Grounds",
        "short_name": "Pszczyna",
        "width": 7.0,
        "theme": "city",
        "barrier": "armco",
        "runoff": 3.5,
        "runoff_surface": "asphalt",
        "runoff_paved": 1.2,
        "kerb_style": "yellow_black",
        "kerb_width": 1.0,
        "tree_density": 0.55,
        "tree_patch": 0.65,
        "tree_conifer": 0.35,
        "grandstands": True,
        "stand_tiers": 3,
        "pit_entry": -220.0,
        "pit_exit": 200.0,
        "pit_offset": 8.5,
        "street_nodes": [
            [0.0, 0.0, 255.0],          # 0: Rynek w Pszczynie (cobblestones by Ratusz)
            [-160.0, 0.0, 255.2],       # 1: Brama Wybrańców stone archway
            [-320.0, -40.0, 255.8],     # 2: Pałac Pszczyński castle courtyard
            [-520.0, -120.0, 256.5],    # 3: Aleja Parkowa through ancient oaks
            [-680.0, -280.0, 257.0],    # 4: Stawy Parkowe (Swan Island pond turn)
            [-720.0, -480.0, 257.5],    # 5: Pszczynka River embankment curve
            [-620.0, -660.0, 258.0],    # 6: Historic Ludwik Pond hairpin
            [-420.0, -740.0, 258.5],    # 7: Park gates exit onto ul. Parkowa
            [-180.0, -700.0, 258.0],    # 8: ul. Wojska Polskiego straight
            [120.0, -640.0, 257.0],     # 9: Wojska Polskiego / Dworcowa intersection
            [220.0, -420.0, 256.0],     # 10: ul. Dworcowa past the railway station
            [210.0, -180.0, 255.5],     # 11: Dworcowa / Piastowska corner
            [120.0, -40.0, 255.0],      # 12: ul. Piastowska returning to Rynek
        ],
        "radii": {
            0: 25.0, 1: 18.0, 2: 24.0, 3: 35.0, 4: 30.0, 5: 35.0,
            6: 22.0, 7: 28.0, 8: 40.0, 9: 20.0, 10: 25.0, 11: 18.0, 12: 24.0
        },
        "corners": [
            (0.0, "Rynek Pszczyński"),
            (180.0, "Brama Wybrańców (1687)"),
            (420.0, "Dziedziniec Pałacu Daisy"),
            (720.0, "Aleja Dębowa Parku"),
            (1050.0, "Zakole Stawu Łabędziego"),
            (1380.0, "Most nad Pszczynką"),
            (1680.0, "Brama Parkowa"),
            (1960.0, "Aleja Wojska Polskiego"),
            (2240.0, "Zakręt Dworcowy"),
            (2480.0, "Ulica Piastowska")
        ],
        "water_polys": [
            # Staw Łabędzi (Swan Lake) in Castle Park
            [-740.0, -220.0, -580.0, -240.0, -600.0, -380.0, -780.0, -360.0],
            # Staw Ludwik
            [-680.0, -560.0, -520.0, -580.0, -560.0, -720.0, -720.0, -690.0]
        ],
        "landmarks": [
            ["CastleKeep", -330.0, -70.0, 45.0, 28.0, 0.3, 24.0],  # Pałac Pszczyński
            ["CastleTower", -160.0, 0.0, 8.0, 8.0, 0.0, 14.0]      # Brama Wybrańców
        ],
        "rynek_rect": [0.0, 0.0, 110.0, 90.0],
        "building_heights": [12.0, 18.0],
        "building_kind": 1
    },

    # 5. OŚWIĘCIM: Bulwary nad Sołą, historic Piast Castle, Rynek, and Most Piastowski river crossing
    {
        "key": "oswiecim",
        "display_name": "Oświęcim Riverfront",
        "short_name": "Oświęcim",
        "width": 7.4,
        "theme": "city",
        "barrier": "armco",
        "runoff": 3.0,
        "runoff_surface": "asphalt",
        "runoff_paved": 1.2,
        "kerb_style": "red_white",
        "kerb_width": 1.0,
        "tree_density": 0.35,
        "tree_patch": 0.55,
        "tree_conifer": 0.15,
        "grandstands": True,
        "stand_tiers": 3,
        "pit_entry": -240.0,
        "pit_exit": 210.0,
        "pit_offset": 8.8,
        "street_nodes": [
            [0.0, 0.0, 228.0],          # 0: Bulwary nad Sołą (riverside promenade)
            [260.0, 20.0, 228.2],       # 1: Bulwary north curve along river
            [460.0, 80.0, 228.5],       # 2: Bulwary / Dąbrowskiego climbing junction
            [540.0, -80.0, 233.0],      # 3: Castle Hill climb past Zamek Piastowski
            [510.0, -280.0, 235.0],     # 4: Entrance to Rynek Główny
            [320.0, -320.0, 235.0],     # 5: Rynek Główny w Oświęcimiu
            [160.0, -310.0, 234.0],     # 6: ul. Jagiełły corner
            [40.0, -480.0, 232.0],      # 7: ul. Zaborska boulevard
            [-160.0, -600.0, 230.5],    # 8: Rondo Solidarności into ul. Legionów
            [-380.0, -520.0, 229.5],    # 9: Most Piastowski (bridge crossing over the Soła River!)
            [-440.0, -320.0, 228.8],    # 10: Zasole bridgehead turn
            [-360.0, -120.0, 228.2],    # 11: ul. Nadrzeczna riverbank straight
            [-180.0, -20.0, 228.0],     # 12: Return curve to Bulwary
        ],
        "radii": {
            0: 45.0, 1: 50.0, 2: 24.0, 3: 20.0, 4: 25.0, 5: 35.0,
            6: 22.0, 7: 35.0, 8: 28.0, 9: 45.0, 10: 20.0, 11: 35.0, 12: 40.0
        },
        "corners": [
            (0.0, "Bulwary Nadsoły"),
            (320.0, "Zakole Rzeki Soły"),
            (610.0, "Wzgórze Zamku Piastowskiego"),
            (880.0, "Rynek Oświęcimski"),
            (1140.0, "Zakręt Jagiełły"),
            (1450.0, "Aleja Zaborska"),
            (1780.0, "Rondo Legionów"),
            (2040.0, "Most Piastowski nad Sołą"),
            (2320.0, "Nadrzeczna S-Bends")
        ],
        "water_polys": [
            # Rzeka Soła flowing between Old Town and Zasole
            [-220.0, 80.0, -260.0, -180.0, -310.0, -420.0, -360.0, -620.0, 
             -440.0, -600.0, -380.0, -400.0, -340.0, -160.0, -300.0, 90.0]
        ],
        "landmarks": [
            ["CastleTower", 540.0, -90.0, 10.0, 10.0, 0.0, 28.0], # Wieża Zamku Piastowskiego
            ["CastleKeep", 530.0, -70.0, 22.0, 16.0, 0.2, 18.0]   # Skrzydło Zamkowe
        ],
        "bridges": [
            [1, -380.0, -520.0, 0.8, -0.6] # Most Piastowski
        ],
        "rynek_rect": [320.0, -320.0, 90.0, 90.0],
        "building_heights": [12.0, 18.0],
        "building_kind": 1
    },

    # 6. BRZESZCZE: Historic mining center — KWK Szyb Andrzej pithead, Dworcowa, railway crossing, mining colony
    {
        "key": "brzeszcze",
        "display_name": "Brzeszcze Industrial Sprint",
        "short_name": "Brzeszcze",
        "width": 7.2,
        "theme": "city",
        "barrier": "armco",
        "runoff": 3.0,
        "runoff_surface": "asphalt",
        "runoff_paved": 1.0,
        "kerb_style": "yellow_black",
        "kerb_width": 1.0,
        "tree_density": 0.25,
        "tree_patch": 0.5,
        "tree_conifer": 0.15,
        "grandstands": True,
        "stand_tiers": 3,
        "pit_entry": -220.0,
        "pit_exit": 200.0,
        "pit_offset": 8.6,
        "street_nodes": [
            [0.0, 0.0, 242.0],          # 0: ul. Kościuszki beside KWK Brzeszcze Szyb Andrzej (1903 headframe)
            [-280.0, -10.0, 242.5],     # 1: ul. Kościuszki miners' cultural house
            [-480.0, -80.0, 243.0],     # 2: Kościuszki / Dworcowa 90° left turn
            [-510.0, -320.0, 244.0],    # 3: ul. Dworcowa past the train station
            [-520.0, -520.0, 244.5],    # 4: Przejazd Kolejowy (industrial rail crossing chicane)
            [-360.0, -680.0, 245.0],    # 5: ul. Mickiewicza through historic brick Kolonia Robotnicza
            [-120.0, -720.0, 246.0],    # 6: Colony avenue straight
            [160.0, -680.0, 247.0],     # 7: Corner onto ul. Ofiar Oświęcimia
            [380.0, -520.0, 247.5],     # 8: Ofiar Oświęcimia stadium straight
            [440.0, -320.0, 246.0],     # 9: Sweeper past Park Miejski
            [360.0, -120.0, 244.0],     # 10: Hałda park chicane
            [180.0, -20.0, 243.0],      # 11: ul. Piastowska approach back to pithead
        ],
        "radii": {
            0: 35.0, 1: 40.0, 2: 18.0, 3: 35.0, 4: 16.0, 5: 22.0,
            6: 35.0, 7: 24.0, 8: 38.0, 9: 28.0, 10: 22.0, 11: 30.0
        },
        "corners": [
            (0.0, "Prosta pod Szybem Andrzej"),
            (320.0, "Zakręt Kościuszki"),
            (620.0, "Dworcowa PKP"),
            (910.0, "Szykana Przejazdu Kolejowego"),
            (1220.0, "Aleja Kolonii Robotniczej"),
            (1540.0, "Ofiar Oświęcimia"),
            (1860.0, "Park Miejski w Brzeszczach"),
            (2180.0, "Powrót Kopalniany")
        ],
        "water_polys": [
            # Staw w Parku Miejskim
            [480.0, -280.0, 560.0, -290.0, 580.0, -420.0, 470.0, -400.0]
        ],
        "landmarks": [
            ["IndyPagoda", 0.0, 40.0, 28.0, 28.0, 0.0, 42.0] # KWK Szyb Andrzej Pithead Headframe representation
        ],
        "building_heights": [12.0, 20.0],
        "building_kind": 2 # Brick colliery buildings and miners' colony terraces
    },

    # 7. WILAMOWICE: Historic town of the Wymysorys culture — Rynek, Mielnicki rollercoaster ridge, Beskid panoramas
    {
        "key": "wilamowice",
        "display_name": "Wilamowice Country Loop",
        "short_name": "Wilamowice",
        "width": 6.8,
        "theme": "country",
        "barrier": "armco",
        "runoff": 3.8,
        "runoff_surface": "grass",
        "runoff_paved": 1.0,
        "kerb_style": "red_white",
        "kerb_width": 1.0,
        "tree_density": 0.55,
        "tree_patch": 0.65,
        "tree_conifer": 0.45,
        "grandstands": True,
        "stand_tiers": 2,
        "pit_entry": -220.0,
        "pit_exit": 200.0,
        "pit_offset": 8.4,
        "street_nodes": [
            [0.0, 0.0, 282.0],          # 0: Rynek w Wilamowicach (town square by Trinity Church)
            [220.0, -20.0, 288.0],      # 1: ul. Paderewskiego uphill climb
            [440.0, -110.0, 298.0],     # 2: Mielnicki Ridge transition
            [680.0, -260.0, 312.0],     # 3: Wymysiöeryś Ridge Crest (spectacular Beskid view at 312m)
            [820.0, -480.0, 308.0],     # 4: Rollercoaster downhill curve
            [740.0, -720.0, 298.0],     # 5: Pola Dankowickie sweeping descent
            [520.0, -880.0, 286.0],     # 6: Dankowice T-Junction 90° right
            [240.0, -840.0, 282.0],     # 7: ul. Więźniów Oświęcimia country tarmac
            [-40.0, -740.0, 280.0],     # 8: Tree-lined rural straight
            [-260.0, -560.0, 281.0],    # 9: ul. Sobieskiego S-bends through old farm estates
            [-320.0, -320.0, 281.5],    # 10: Stara Droga village chicane
            [-180.0, -120.0, 282.0],    # 11: Final approach to Rynek
        ],
        "radii": {
            0: 25.0, 1: 35.0, 2: 30.0, 3: 40.0, 4: 28.0, 5: 35.0,
            6: 18.0, 7: 40.0, 8: 38.0, 9: 24.0, 10: 22.0, 11: 26.0
        },
        "corners": [
            (0.0, "Rynek Wilamowicki"),
            (280.0, "Podjazd Paderewskiego"),
            (620.0, "Grzbiet Mielnicki"),
            (980.0, "Wymysiöeryś Rollercoaster (312m)"),
            (1340.0, "Pola Dankowickie"),
            (1680.0, "Zakręt na Więźniów Oświęcimia"),
            (2040.0, "Aleja Sobieskiego"),
            (2380.0, "Szykana Starej Wsi")
        ],
        "water_polys": [
            # Stawy Hodowlane w Dankowicach (fish ponds)
            [540.0, -740.0, 680.0, -760.0, 660.0, -860.0, 520.0, -840.0]
        ],
        "landmarks": [
            ["CastleTower", 0.0, 25.0, 8.0, 8.0, 0.0, 24.0] # Kościół Narodzenia NMP w Wilamowicach
        ],
        "rynek_rect": [0.0, 0.0, 70.0, 70.0],
        "building_heights": [8.0, 14.0],
        "building_kind": 0 # Village houses & cottages
    },

    # 8. BÓR (Brzeszcze Bór): Historic Silesian forest loop based on real streets (ul. Bór, ul. Strażacka, ul. Borska)
    {
        "key": "bor",
        "display_name": "Bór Forest Stage",
        "short_name": "Bór",
        "width": 6.8,
        "theme": "forest",
        "barrier": "armco",
        "runoff": 1.8,
        "runoff_surface": "grass",
        "runoff_paved": 0.0,
        "kerb_style": "none",
        "kerb_width": 0.0,
        "tree_density": 0.85,
        "tree_patch": 0.75,
        "tree_conifer": 0.82,
        "grandstands": False,
        "stand_tiers": 0,
        "pit_entry": -220.0,
        "pit_exit": 200.0,
        "pit_offset": 8.4,
        "street_nodes": [
            [0.0, 0.0, 238.0],          # 0: ul. Bór / Strażacka junction (Start / Finish line)
            [30.0, -180.0, 238.5],      # 1: ul. Strażacka railway grade crossing
            [50.0, -420.0, 239.0],      # 2: Strażacka / Borska corner (sharp left into Borska)
            [-220.0, -520.0, 239.5],    # 3: ul. Borska northern forest straight
            [-540.0, -640.0, 240.0],    # 4: ul. Borska sweeping curve past Stawy Północne
            [-780.0, -740.0, 240.5],    # 5: Borska western junction (left into forest road)
            [-920.0, -540.0, 241.0],    # 6: Leśna Droga (forest descent through tall pines)
            [-960.0, -320.0, 240.5],    # 7: Western railway line crossing
            [-940.0, -100.0, 239.5],    # 8: Staw Bór lakeside approach
            [-840.0, 80.0, 238.5],      # 9: Scenic water embankment curve (heart icon in map)
            [-620.0, 110.0, 238.2],     # 10: Lakeside straight along Staw Bór
            [-380.0, 70.0, 238.0],      # 11: ul. Bór western entry into the settlement
            [-180.0, 30.0, 238.0],      # 12: ul. Bór village straight past houses
        ],
        "radii": {
            0: 24.0, 1: 50.0, 2: 22.0, 3: 45.0, 4: 50.0, 5: 25.0,
            6: 35.0, 7: 40.0, 8: 30.0, 9: 35.0, 10: 45.0, 11: 30.0, 12: 35.0
        },
        "corners": [
            (0.0, "Prosta Osiedla Bór"),
            (180.0, "Przejazd Kolejowy Strażacka"),
            (450.0, "Zakręt na Borska"),
            (820.0, "Aleja Borska pod Lasem"),
            (1240.0, "Zakręt Stawów Północnych"),
            (1580.0, "Wjazd w Las Sosnowy"),
            (1920.0, "Leśny Przejazd Kolejowy"),
            (2240.0, "Grobla Stawu Bór"),
            (2620.0, "Nawrót Nadwodny"),
            (2850.0, "Ulica Bór")
        ],
        "water_polys": [
            # Staw Bór (scenic lake on bottom-left)
            [-1060.0, -40.0, -780.0, 160.0, -560.0, 190.0, -620.0, 360.0, -980.0, 340.0, -1120.0, 140.0],
            # Stawy Północne (above Borska)
            [-860.0, -820.0, -420.0, -680.0, -320.0, -880.0, -780.0, -980.0],
            [-220.0, -580.0, 120.0, -520.0, 180.0, -720.0, -120.0, -780.0]
        ],
        "landmarks": [
            ["CastleTower", -900.0, -480.0, 8.0, 8.0, 0.0, 26.0], # Leśna wieża pożarowa
            ["CastleKeep", 20.0, -380.0, 20.0, 16.0, 0.2, 14.0]   # Leśniczówka Strażacka
        ],
        "railway_line": [[-1100.0, -280.0], [240.0, -130.0]],
        "building_heights": [6.0, 8.0],
        "building_kind": 0,
        "road_blockages": [
            [18.0, 0.0, 1.5708, 7.5],
            [-6.0, -65.0, 1.5708, 5.0],
            [38.0, -120.0, 1.5708, 6.0],
            [45.0, -168.0, 1.92, 5.5],
            [10.0, -172.0, 1.92, 5.5],
            [56.0, -310.0, 1.5708, 5.5],
            [50.0, -438.0, 0.0, 8.5],
            [-85.0, -460.0, -0.95, 6.0],
            [-380.0, -598.0, 0.0, 5.5],
            [-645.0, -670.0, 0.95, 6.0],
            [-798.0, -744.0, 1.17, 7.5],
            [-948.0, -440.0, 1.5708, 5.0],
            [-978.0, -312.0, 1.92, 5.5],
            [-942.0, -328.0, 1.92, 5.5],
            [-925.0, -35.0, 0.80, 5.0],
            [-705.0, 115.0, 0.0, 5.5],
            [-480.0, 102.0, 0.0, 5.5],
            [-280.0, 36.0, 0.0, 6.0],
            [-120.0, 36.0, 0.0, 5.5]
        ]
    }
]


def generate_bor_buildings(rx, ry, cfg):
    """
    Generate authentic real-life Polish rural single-family houses (domki jednorodzinne)
    exclusively in the residential settlement of Bór:
    1. Hugging ul. Bór (from x ≈ -650 to x ≈ 0 along track, and east continuation to x ≈ +180)
    2. Southern half of ul. Strażacka (from junction y ≈ 0 to y ≈ -140, just north of railway crossing)
    NO buildings along ul. Borska (fishponds and fields).
    NO buildings in the western pine woods.
    NO buildings on the railway line.
    NO buildings along Staw Bór lake.
    Authentic detached homes:
    - width 9-14m, depth 9-13m, height 6-8m, pitched roofs (kind: 0 or 4)
    - placed in gardens set back ~8-15m from ul. Bór and ul. Strażacka.
    """
    np.random.seed(42)
    buildings = []
    trees = []
    road_clear = cfg["width"] * 0.5 + cfg["runoff"]

    diffs = np.roll(np.column_stack([rx, ry]), -1, axis=0) - np.column_stack([rx, ry])
    lengths = np.hypot(diffs[:, 0], diffs[:, 1])
    tangents = diffs / np.maximum(lengths[:, None], 1e-4)
    normals = np.column_stack([-tangents[:, 1], tangents[:, 0]])
    N = len(rx)

    def add_house(p, tangent, norm, side, setback, w, d, h, kind):
        levels = max(1, int(round(h / 3.5)))
        center_dist = road_clear + setback + d * 0.5
        center_pt = p + side * norm * center_dist
        u = tangent * (w * 0.5)
        v = norm * (side * d * 0.5)
        c0 = center_pt - u - v
        c1 = center_pt + u - v
        c2 = center_pt + u + v
        c3 = center_pt - u + v
        buildings.append([
            round(h, 1),
            kind,
            levels,
            round(float(c0[0]), 2), round(float(c0[1]), 2),
            round(float(c1[0]), 2), round(float(c1[1]), 2),
            round(float(c2[0]), 2), round(float(c2[1]), 2),
            round(float(c3[0]), 2), round(float(c3[1]), 2)
        ])
        for _ in range(np.random.randint(1, 3)):
            t_dist = road_clear + np.random.uniform(2.0, setback + d * 0.25)
            t_side = side * norm * t_dist + tangent * np.random.uniform(-w * 0.6, w * 0.6)
            t_pt = p + t_side
            trees.extend([round(float(t_pt[0]), 2), round(float(t_pt[1]), 2)])

    # 1. Along track: ul. Bór (from x ≈ -650 to x ≈ 0)
    for i in range(0, N, 12):
        px = rx[i]
        py = ry[i]
        if px >= -650.0 and px <= 5.0 and py >= -10.0 and py <= 115.0:
            p = np.array([px, py])
            tangent = tangents[i]
            norm = normals[i]
            for side in [-1.0, 1.0]:
                w = float(np.random.uniform(9.0, 14.0))
                d = float(np.random.uniform(9.0, 13.0))
                h = float(np.random.uniform(6.0, 8.0))
                kind = int(np.random.choice([0, 4]))
                setback = float(np.random.uniform(8.0, 15.0))
                add_house(p, tangent, norm, side, setback, w, d, h, kind)

    # 2. Along track: ul. Strażacka (from junction y ≈ 0 to y ≈ -140)
    for i in range(0, N, 12):
        px = rx[i]
        py = ry[i]
        if py < 0.0 and py >= -140.0 and px >= -5.0 and px <= 35.0:
            p = np.array([px, py])
            tangent = tangents[i]
            norm = normals[i]
            for side in [-1.0, 1.0]:
                w = float(np.random.uniform(9.0, 14.0))
                d = float(np.random.uniform(9.0, 13.0))
                h = float(np.random.uniform(6.0, 8.0))
                kind = int(np.random.choice([0, 4]))
                setback = float(np.random.uniform(8.0, 15.0))
                add_house(p, tangent, norm, side, setback, w, d, h, kind)

    # 3. Eastern continuation of ul. Bór (from x ≈ 15.0 to x ≈ 180.0)
    east_tangent = np.array([0.997, -0.076])
    east_norm = np.array([0.076, 0.997])
    for ex in np.arange(20.0, 180.0, 26.0):
        ey = -ex * 0.076
        p = np.array([ex, ey])
        for side in [-1.0, 1.0]:
            w = float(np.random.uniform(9.0, 14.0))
            d = float(np.random.uniform(9.0, 13.0))
            h = float(np.random.uniform(6.0, 8.0))
            kind = int(np.random.choice([0, 4]))
            setback = float(np.random.uniform(8.0, 15.0))
            add_house(p, east_tangent, east_norm, side, setback, w, d, h, kind)

    # 4. Dense pine woods trees along the forest stage sections (Borska, Leśna Droga, Staw Bór)
    for i in range(0, N, 8):
        px = rx[i]
        py = ry[i]
        is_residential = (px >= -650.0 and px <= 180.0 and py >= -140.0 and py <= 115.0)
        if not is_residential:
            p = np.array([px, py])
            norm = normals[i]
            for side in [-1.0, 1.0]:
                if np.random.rand() < 0.85:
                    t_dist = road_clear + np.random.uniform(1.5, 9.0)
                    t_pt = p + side * norm * t_dist
                    trees.extend([round(float(t_pt[0]), 2), round(float(t_pt[1]), 2)])

    return buildings, trees


def generate_street_buildings(rx, ry, cfg):
    """
    Generate authentic urban building footprints along both sides of the street with realistic setbacks.
    """
    buildings = []
    trees = []
    N = len(rx)
    
    # Calculate track normals along centerline
    diffs = np.roll(np.column_stack([rx, ry]), -1, axis=0) - np.column_stack([rx, ry])
    lengths = np.hypot(diffs[:, 0], diffs[:, 1])
    tangents = diffs / np.maximum(lengths[:, None], 1e-4)
    # Normals pointing left (+90 deg)
    normals = np.column_stack([-tangents[:, 1], tangents[:, 0]])
    
    road_clear = cfg["width"] * 0.5 + cfg["runoff"] + 2.0
    
    # Place building blocks along the street
    stride = 14 # samples between building lots (~28m)
    for i in range(0, N, stride):
        # Keep start/finish straight and pit building corridor clear (+/- 260m)
        s_dist = min(i * 2.0, (N - i) * 2.0)
        if s_dist < 260.0:
            continue
        p = np.array([rx[i], ry[i]])
        tangent = tangents[i]
        norm = normals[i]
        
        # Determine building dimensions
        h_min, h_max = cfg["building_heights"]
        
        for side in [-1.0, 1.0]:
            # Skip if near water
            h = float(np.random.uniform(h_min, h_max))
            kind = cfg["building_kind"]
            levels = max(1, int(round(h / 3.5)))
            
            # Width along road, depth back
            w = float(np.random.uniform(16.0, 24.0))
            d = float(np.random.uniform(14.0, 22.0))
            
            # Setback distance: front wall sits ~road_clear + 5.5m
            center_dist = road_clear + 5.5 + d * 0.5
            center_pt = p + side * norm * center_dist
            
            # Corner vertices of rectangular building footprint
            # u along tangent, v along normal * side
            u = tangent * (w * 0.5)
            v = norm * (side * d * 0.5)
            
            c0 = center_pt - u - v
            c1 = center_pt + u - v
            c2 = center_pt + u + v
            c3 = center_pt - u + v
            
            b_entry = [
                round(h, 1),
                kind,
                levels,
                round(float(c0[0]), 2), round(float(c0[1]), 2),
                round(float(c1[0]), 2), round(float(c1[1]), 2),
                round(float(c2[0]), 2), round(float(c2[1]), 2),
                round(float(c3[0]), 2), round(float(c3[1]), 2)
            ]
            buildings.append(b_entry)
            
            # Add street trees between buildings or on sidewalks
            if np.random.rand() < cfg["tree_density"] * 0.7:
                tree_pt = p + side * norm * (road_clear + 1.2)
                trees.extend([round(float(tree_pt[0]), 2), round(float(tree_pt[1]), 2)])
                
    # Add extra buildings surrounding Rynek (town square) if defined
    if "rynek_rect" in cfg:
        rx0, ry0, rw, rh = cfg["rynek_rect"]
        for side_idx, (sx, sy, sw, sh) in enumerate([
            (rx0, ry0 - rh*0.6, rw, 18.0),
            (rx0, ry0 + rh*0.6, rw, 18.0),
            (rx0 - rw*0.6, ry0, 18.0, rh),
            (rx0 + rw*0.6, ry0, 18.0, rh)
        ]):
            h = float(np.random.uniform(16.0, 22.0))
            c0 = [sx - sw*0.5, sy - sh*0.5]
            c1 = [sx + sw*0.5, sy - sh*0.5]
            c2 = [sx + sw*0.5, sy + sh*0.5]
            c3 = [sx - sw*0.5, sy + sh*0.5]
            buildings.append([
                round(h, 1), 1, int(h/3.5),
                round(c0[0], 2), round(c0[1], 2),
                round(c1[0], 2), round(c1[1], 2),
                round(c2[0], 2), round(c2[1], 2),
                round(c3[0], 2), round(c3[1], 2)
            ])
            
    return buildings, trees


def generate_land_map(rx, ry, buildings, water_polys, cfg, land_rect, tex_size=1024):
    """
    Generate authentic land map texture:
    R: Paved (streets, sidewalks, buildings, plazas)
    G: Farmland, grass lawns, park greensward
    B: Bare ground, cobblestones, gravel
    A: Forest & tree canopy density
    """
    x0, y0, w, h = land_rect
    img = Image.new("RGBA", (tex_size, tex_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Scale helper
    def to_px(x, y):
        px = int((x - x0) / w * tex_size)
        py = int((y - y0) / h * tex_size)
        return (px, py)
        
    # 1. Base terrain background
    theme = cfg.get("theme", "city")
    if theme == "forest":
        base_col = (15, 110, 20, 225) # dense dark pine forest
    elif theme == "city":
        base_col = (50, 140, 50, 20) # urban grass & lawns
    else:
        base_col = (20, 195, 30, 40) # rural fields
    draw.rectangle([0, 0, tex_size, tex_size], fill=base_col)

    # Railway ballast line if present
    if "railway_line" in cfg:
        r_pts = [to_px(p[0], p[1]) for p in cfg["railway_line"]]
        draw.line(r_pts, fill=(90, 45, 230, 0), width=max(2, int(8.0 / w * tex_size)))
    
    # 2. Water polygons
    for wp in water_polys:
        pts = [to_px(wp[k], wp[k+1]) for k in range(0, len(wp), 2)]
        if len(pts) >= 3:
            draw.polygon(pts, fill=(0, 20, 10, 0)) # Clean riverbed
            
    # 3. Rynek / Town square cobblestones
    if "rynek_rect" in cfg:
        rx0, ry0, rw, rh = cfg["rynek_rect"]
        p0 = to_px(rx0 - rw*0.55, ry0 - rh*0.55)
        p1 = to_px(rx0 + rw*0.55, ry0 + rh*0.55)
        draw.rectangle([p0, p1], fill=(190, 40, 210, 0)) # Cobblestone plaza
        
    # 4. Dense park canopy (e.g. Kraków Planty, Pszczyna Castle Park)
    if cfg["key"] in ["krakow", "pszczyna"]:
        poly_pts = [to_px(rx[k], ry[k]) for k in range(0, len(rx), 4)]
        if len(poly_pts) >= 3:
            draw.line(poly_pts, fill=(30, 120, 30, 230), width=int(35.0 / w * tex_size))
            
    # 5. Sidewalks buffer along the track
    track_pts = [to_px(rx[k], ry[k]) for k in range(len(rx))]
    sidewalk_px = max(2, int((cfg["width"] + 12.0) / w * tex_size))
    draw.line(track_pts + [track_pts[0]], fill=(210, 30, 90, 0), width=sidewalk_px)
    
    # 6. Track asphalt surface
    road_px = max(2, int(cfg["width"] / w * tex_size))
    draw.line(track_pts + [track_pts[0]], fill=(255, 10, 15, 0), width=road_px)
    
    # 7. Building footprints
    for b in buildings:
        b_pts = [to_px(b[k], b[k+1]) for k in range(3, 11, 2)]
        draw.polygon(b_pts, fill=(240, 20, 25, 0))
        
    return img


def main():
    tracks_dir = os.path.join(os.path.dirname(__file__), "..", "godot", "data", "tracks")
    os.makedirs(tracks_dir, exist_ok=True)
    
    print("=" * 75)
    print("BUILDING REAL CITY CIRCUITS, 3D SURROUNDINGS & LAND MAPS FOR SEICENTO")
    print("=" * 75)
    
    for cfg in STREET_TRACKS:
        key = cfg["key"]
        print(f"\n--- Processing: {cfg['display_name']} ({key}) ---")
        if os.path.exists(os.path.join(os.path.dirname(__file__), "street_routes", key + ".json")):
            print("  skipped: built from OpenStreetMap by tools/build_street_tracks.py")
            continue
        
        n_samples, actual_step, total_L, rx, ry, rz = fillet_path(
            cfg["street_nodes"],
            cfg["radii"],
            default_radius=22.0
        )
        
        print(f"  Geometry: {n_samples} points, {actual_step:.4f}m step, {total_L:.1f}m length")
        print(f"  Elevation: {np.min(rz):.1f}m to {np.max(rz):.1f}m (climb: {np.max(rz)-np.min(rz):.1f}m)")
        
        # Interleave 2D points [x0, y0, x1, y1, ...]
        pts = []
        for x, y in zip(rx, ry):
            pts.append(round(float(x), 2))
            pts.append(round(float(y), 2))
            
        elev = [round(float(z), 2) for z in rz]
        dem = generate_dem_grid(rx, ry, rz)
        
        # 1. Build JSON dictionary (<key>.json)
        json_data = {
            "pts": pts,
            "step": round(actual_step, 6),
            "length": round(total_L, 2),
            "elev": elev,
            "grid": dem
        }
        
        if "tunnel_range" in cfg:
            t_start = int(round(n_samples * cfg["tunnel_range"][0]))
            t_end = int(round(n_samples * cfg["tunnel_range"][1]))
            json_data["tunnels"] = [[t_start, t_end]]
            print(f"  Tunnels: indices {t_start} to {t_end}")
            
        json_path = os.path.join(tracks_dir, f"{key}.json")
        with open(json_path, "w") as f:
            json.dump(json_data, f, separators=(',', ':'))
        print(f"  [OK] Wrote: {json_path}")
        
        # 2. Build .tres TrackDef resource (<key>.tres)
        tres_lines = [
            '[gd_resource type="Resource" script_class="TrackDef" format=3]',
            '',
            '[ext_resource type="Script" path="res://scripts/data/corner_name.gd" id="1"]',
            '[ext_resource type="Script" path="res://scripts/data/track_def.gd" id="2"]',
            ''
        ]
        
        sub_resources = []
        corner_refs = []
        for idx, (dist, name) in enumerate(cfg["corners"]):
            sub_id = f"SubResource(\"{idx + 1}\")"
            corner_refs.append(sub_id)
            sub_resources.extend([
                f'[sub_resource type="Resource" id="{idx + 1}"]',
                'script = ExtResource("1")',
                f'd = {dist:.1f}',
                f'name = "{name}"',
                ''
            ])
            
        tres_lines.extend(sub_resources)
        tres_lines.extend([
            '[resource]',
            'script = ExtResource("2")',
            f'key = "{key}"',
            f'display_name = "{cfg["display_name"]}"',
            f'short_name = "{cfg["short_name"]}"',
            f'width = {cfg["width"]:.1f}',
            f'theme = "{cfg["theme"]}"',
            f'barrier = "{cfg["barrier"]}"',
            f'runoff = {cfg["runoff"]:.1f}',
            f'runoff_surface = "{cfg["runoff_surface"]}"',
            f'runoff_paved = {cfg["runoff_paved"]:.1f}',
            f'kerb_style = "{cfg["kerb_style"]}"',
            f'kerb_width = {cfg["kerb_width"]:.1f}',
            f'tree_density = {cfg["tree_density"]:.2f}',
            f'tree_patch = {cfg["tree_patch"]:.2f}',
            f'tree_conifer = {cfg["tree_conifer"]:.2f}',
            f'grandstands = {"true" if cfg.get("grandstands") else "false"}',
            f'stand_tiers = {cfg.get("stand_tiers", 3)}',
            f'pit_entry = {cfg.get("pit_entry", -200.0):.1f}',
            f'pit_exit = {cfg.get("pit_exit", 200.0):.1f}',
            f'pit_offset = {cfg.get("pit_offset", 8.5):.1f}',
            f'corners = [{" ,".join(corner_refs)}]'
        ])
        
        tres_path = os.path.join(tracks_dir, f"{key}.tres")
        with open(tres_path, "w") as f:
            f.write("\n".join(tres_lines) + "\n")
        print(f"  [OK] Wrote: {tres_path}")
        
        # 3. Generate 3D Surroundings & Land Map (<key>_env.json and <key>_land.png)
        padding = 220.0
        min_x = float(np.min(rx)) - padding
        max_x = float(np.max(rx)) + padding
        min_y = float(np.min(ry)) - padding
        max_y = float(np.max(ry)) + padding
        land_rect = [round(min_x, 1), round(min_y, 1), round(max_x - min_x, 1), round(max_y - min_y, 1)]
        
        if key == "bor":
            buildings, trees = generate_bor_buildings(rx, ry, cfg)
        else:
            buildings, trees = generate_street_buildings(rx, ry, cfg)
        water_polys = cfg.get("water_polys", [])
        landmarks = cfg.get("landmarks", [])
        bridges = cfg.get("bridges", [])
        
        # Grandstands near start/finish
        stands = []
        if cfg.get("grandstands"):
            s_pts = [
                round(float(rx[0] + 12.0), 2), round(float(ry[0] - 6.0), 2),
                round(float(rx[0] + 12.0), 2), round(float(ry[0] + 55.0), 2),
                round(float(rx[0] + 24.0), 2), round(float(ry[0] + 55.0), 2),
                round(float(rx[0] + 24.0), 2), round(float(ry[0] - 6.0), 2),
            ]
            stands.append(s_pts)
            
        env_data = {
            "land": {
                "x0": land_rect[0],
                "y0": land_rect[1],
                "w": land_rect[2],
                "h": land_rect[3]
            },
            "buildings": buildings,
            "water": water_polys,
            "rivers": [],
            "stands": stands,
            "bridges": bridges,
            "hedges": [],
            "trees": trees,
            "towers": [],
            "landmarks": landmarks,
            "pools": [],
            "road_blockages": cfg.get("road_blockages", [])
        }
        
        env_path = os.path.join(tracks_dir, f"{key}_env.json")
        with open(env_path, "w") as f:
            json.dump(env_data, f, separators=(',', ':'))
        print(f"  [OK] Wrote: {env_path} ({len(buildings)} buildings, {len(water_polys)} water bodies, {len(landmarks)} landmarks)")
        
        # 4. Generate Land Map Image (<key>_land.png)
        land_img = generate_land_map(rx, ry, buildings, water_polys, cfg, land_rect, tex_size=1024)
        land_img_path = os.path.join(tracks_dir, f"{key}_land.png")
        land_img.save(land_img_path, format="PNG")
        print(f"  [OK] Wrote: {land_img_path} (1024x1024 RGBA land texture)")
        
    print("\n" + "=" * 75)
    print("ALL 7 CITY CIRCUITS & SURROUNDINGS SUCCESSFULLY GENERATED!")
    print("=" * 75)

if __name__ == "__main__":
    main()
