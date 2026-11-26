// Generated from resources/data/regions.json. Do not edit by hand.
export const REGION_BOUNDS: Readonly<Record<string, { minX: number; minY: number; maxX: number; maxY: number }>> = Object.freeze({
  "castle_royal_gardens": {
    "minX": -544,
    "minY": -714,
    "maxX": 3800,
    "maxY": 7200
  },
  "gothic_castle_boss_zone": {
    "minX": -400,
    "minY": -320,
    "maxX": 3200,
    "maxY": 1600
  },
  "six_zone_royal_gardens": {
    "minX": -3138,
    "minY": 12,
    "maxX": 3150,
    "maxY": 3185
  },
  "six_zone_royal_gate": {
    "minX": -3020,
    "minY": -70,
    "maxX": 3280,
    "maxY": 3080
  },
  "six_zone_willow_fields": {
    "minX": -3168,
    "minY": 0,
    "maxX": 3232,
    "maxY": 3200
  },
  "six_zone_elderwood_grove": {
    "minX": -3200,
    "minY": -16,
    "maxX": 3200,
    "maxY": 3184
  },
  "six_zone_forsaken_ruins": {
    "minX": -3200,
    "minY": -16,
    "maxX": 3200,
    "maxY": 3184
  },
  "six_zone_ruined_tower": {
    "minX": -3200,
    "minY": -16,
    "maxX": 3200,
    "maxY": 3184
  }
});
export const REGION_SPAWNS: Readonly<Record<string, { x: number; y: number }>> = Object.freeze({
  "castle_royal_gardens": {
    "x": 640,
    "y": 620.16
  },
  "elderwood_grove": {
    "x": 0,
    "y": 256
  },
  "forsaken_ruins": {
    "x": 0,
    "y": 256
  },
  "gothic_castle_boss_zone": {
    "x": 0,
    "y": 0
  },
  "greenward": {
    "x": 0,
    "y": 256
  },
  "moonpetal_hollow": {
    "x": 0,
    "y": 192
  },
  "royal_gate": {
    "x": 0,
    "y": 256
  },
  "ruined_tower": {
    "x": 0,
    "y": 256
  },
  "willow_fields": {
    "x": 0,
    "y": 256
  },
  "six_zone_royal_gardens": {
    "x": -1320,
    "y": 2325
  },
  "six_zone_royal_gate": {
    "x": 0,
    "y": 900
  },
  "six_zone_willow_fields": {
    "x": -2450,
    "y": 1370
  },
  "six_zone_elderwood_grove": {
    "x": -1600,
    "y": 1050
  },
  "six_zone_forsaken_ruins": {
    "x": -1600,
    "y": 1050
  },
  "six_zone_ruined_tower": {
    "x": 0,
    "y": 2460
  }
});
export const EXPEDITION_PORTALS: Readonly<Record<string, Record<string, [number,number]>>> = {
  "six_zone_royal_gardens": {
    "six_zone_royal_gate": [
      1576,
      2380
    ]
  },
  "six_zone_royal_gate": {
    "six_zone_willow_fields": [
      1664,
      2432
    ],
    "six_zone_royal_gardens": [
      -521,
      200
    ]
  },
  "six_zone_willow_fields": {
    "six_zone_royal_gate": [
      -2720,
      1360
    ],
    "six_zone_elderwood_grove": [
      2624,
      1568
    ]
  },
  "six_zone_elderwood_grove": {
    "six_zone_willow_fields": [
      -1744,
      800
    ],
    "six_zone_forsaken_ruins": [
      1664,
      2432
    ]
  },
  "six_zone_forsaken_ruins": {
    "six_zone_ruined_tower": [
      1664,
      2432
    ],
    "six_zone_elderwood_grove": [
      -1744,
      800
    ]
  },
  "six_zone_ruined_tower": {
    "six_zone_forsaken_ruins": [
      0,
      3050
    ]
  }
};
