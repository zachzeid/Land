#!/bin/bash
# Automated tileset generation using PixelLab API
# Requires: PIXELLAB_API_KEY environment variable

set -e

API_BASE="https://api.pixellab.ai"
OUTPUT_DIR="$(dirname "$0")/../../assets/generated/tilesets"

# Check API key
if [ -z "$PIXELLAB_API_KEY" ]; then
    echo "Error: PIXELLAB_API_KEY not set"
    exit 1
fi

# Function to create tileset and wait for completion
create_tileset() {
    local name="$1"
    local lower="$2"
    local upper="$3"
    local transition="$4"

    echo "Creating tileset: $name"

    # Create tileset (you'd need to check PixelLab's actual REST API docs)
    # This is a placeholder - MCP wraps the API differently
    response=$(curl -s -X POST "$API_BASE/v1/tilesets/topdown" \
        -H "Authorization: Bearer $PIXELLAB_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"lower_description\": \"$lower\",
            \"upper_description\": \"$upper\",
            \"transition_description\": \"$transition\",
            \"transition_size\": 0.25,
            \"tile_size\": {\"width\": 16, \"height\": 16},
            \"view\": \"high top-down\",
            \"detail\": \"low detail\",
            \"shading\": \"flat shading\"
        }")

    tileset_id=$(echo "$response" | jq -r '.id')
    echo "Tileset ID: $tileset_id"

    # Poll until complete
    while true; do
        status=$(curl -s "$API_BASE/v1/tilesets/$tileset_id" \
            -H "Authorization: Bearer $PIXELLAB_API_KEY" | jq -r '.status')

        if [ "$status" = "completed" ]; then
            break
        fi
        echo "  Status: $status, waiting..."
        sleep 10
    done

    # Download files
    curl -s "$API_BASE/mcp/tilesets/$tileset_id/image" -o "$OUTPUT_DIR/${name}_image.png"
    curl -s "$API_BASE/mcp/tilesets/$tileset_id/metadata" -o "$OUTPUT_DIR/${name}_metadata.json"

    echo "Downloaded: ${name}_image.png, ${name}_metadata.json"
}

# Generate tilesets
create_tileset "grass_dirt" \
    "lush green grass field, natural meadow texture, varied green shades" \
    "brown dirt road, smooth packed earth, natural soil texture, earthy brown tones, no brick pattern" \
    "grass naturally blending into dirt, organic edge"

create_tileset "grass_cobblestone" \
    "lush green grass field, natural meadow texture, varied green shades" \
    "gray flagstone pavement, large flat stone slabs, medieval plaza floor, neutral gray tones" \
    "grass meeting flat stone edge"

# Run Godot converter
echo "Running tileset converter..."
/Applications/Godot.app/Contents/MacOS/Godot --headless --path "$(dirname "$0")/../.." --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path "$(dirname "$0")/../.." --script scripts/generation/tileset_converter.gd

echo "Done!"
