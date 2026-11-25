REVERIE — ROYAL GARDENS CLEANED SPRITE EXTRACTION

CONTENTS
- individual_pngs/sheet_XX/: extracted PNG crops, one connected visible sprite region per file
- original_sheets/: the six source sheets for reference
- manifest.json: crop dimensions, source coordinates, and extraction details
- contact_sheets/: visual previews of the extracted crops on a checkerboard

BACKGROUND CLEANUP
The source sheets contained a faint semi-transparent colored backdrop. Extraction uses visible-alpha sprite cores and retains only a narrow antialias fringe around each detected region; pixels outside that fringe are set to alpha 0. The resulting PNG crops have transparent surroundings rather than the original broad backdrop haze.

INDIVIDUAL EXTRACTION LIMIT
Where two objects touch or overlap in the generated source sheet, connected-component extraction can keep them together in one crop. Those grouped crops are identified by their larger bounding boxes and may need manual separation. Inspect before importing.

32x32 GRID
These crops preserve their natural pixel dimensions; they have NOT been forcibly resized to 32x32. Ground/path/fence connection tiles must be individually checked and normalized to exact 32x32 dimensions in the next production pass. Large props (trees, fountains, gates, castle sections, gazebos) should remain multi-tile sprites aligned to the 32px grid.

GODOT
Treat this as a cleaned source-art pack, not a finished TileSet. Validate each tile's edge continuity, pivot/origin, scale, collision, and walkability in the Godot editor before use.
