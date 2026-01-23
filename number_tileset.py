#!/usr/bin/env python3
"""
Number Tileset Utility
Creates a numbered version of your tileset for easy tile identification.
"""

from PIL import Image, ImageDraw, ImageFont
import os

def number_tileset(tileset_path, output_path=None):
    """Add numbers to each 16x16 tile in the tileset"""

    if not os.path.exists(tileset_path):
        print(f"ERROR: Tileset file not found: {tileset_path}")
        return False

    # Load the tileset
    img = Image.open(tileset_path)
    width, height = img.size

    # Create a copy to draw on
    numbered_img = img.copy()
    draw = ImageDraw.Draw(numbered_img)

    # Try to use a nice font, fallback to default if not available
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 12)
    except:
        try:
            font = ImageFont.truetype("arial.ttf", 12)
        except:
            font = ImageFont.load_default()

    tile_size = 16
    tiles_per_row = width // tile_size
    tiles_per_col = height // tile_size
    tile_number = 1

    print(f"Processing tileset: {width}x{height} pixels")
    print(f"Tiles per row: {tiles_per_row}, Tiles per column: {tiles_per_col}")
    print(f"Total tiles: {tiles_per_row * tiles_per_col}")

    # Draw numbers on each tile
    for row in range(tiles_per_col):
        for col in range(tiles_per_row):
            x = col * tile_size + 2
            y = row * tile_size + 2

            # Draw semi-transparent background for number
            bbox = draw.textbbox((x, y), str(tile_number), font=font)
            draw.rectangle([bbox[0]-1, bbox[1]-1, bbox[2]+1, bbox[3]+1],
                          fill=(0, 0, 0, 180))

            # Draw the number
            draw.text((x, y), str(tile_number), fill=(255, 255, 0), font=font)

            tile_number += 1

    # Save the numbered tileset
    if output_path is None:
        base_name = os.path.splitext(tileset_path)[0]
        output_path = f"{base_name}-numbered.png"

    numbered_img.save(output_path)
    print(f"SUCCESS: Numbered tileset saved as: {output_path}")

    return True

def print_tile_reference(width, height, tile_size=16):
    """Print a reference grid showing tile numbers"""
    tiles_per_row = width // tile_size
    tiles_per_col = height // tile_size

    print("\nTILE NUMBER REFERENCE GRID:")
    print("Each number represents a tile index (1-based, left to right, top to bottom)")
    print()

    tile_number = 1
    for row in range(tiles_per_col):
        row_str = f"Row {row+1:2d}: "
        for col in range(tiles_per_row):
            row_str += f"{tile_number:3d} "
            tile_number += 1
        print(row_str)

    print(f"\nTOTAL TILES: {tile_number - 1}")

if __name__ == "__main__":
    tileset_path = "assets/img/tileset/tileset-v1.png"

    # First try to get image dimensions without loading
    try:
        with Image.open(tileset_path) as img:
            width, height = img.size
            print(f"Found tileset: {width}x{height} pixels")

            # Print reference grid
            print_tile_reference(width, height)

            # Create numbered version
            success = number_tileset(tileset_path)

            if success:
                print("\n🎉 Numbered tileset created successfully!")
                print("📖 ROAD TILE IDENTIFICATION GUIDE:")
                print("\nLook at your new 'tileset-v1-numbered.png' file and identify:")
                print("• STRAIGHT_NS: Vertical straight road")
                print("• STRAIGHT_EW: Horizontal straight road")
                print("• CORNER_NE/SE/SW/NW: Corner pieces")
                print("• T_NORTH/EAST/SOUTH/WEST: T-junctions")
                print("• CROSS: 4-way intersection")
                print("• DEAD_END_N/E/S/W: Dead ends")
                print("\n📝 Reply with: 'STRAIGHT_NS = 35, STRAIGHT_EW = 36, ...'")

    except FileNotFoundError:
        print(f"ERROR: Could not find tileset file: {tileset_path}")
        print("Make sure you're running this from the love-game directory")
    except Exception as e:
        print(f"ERROR: {e}")