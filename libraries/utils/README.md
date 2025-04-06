# FastTrackStudio Scripts Utilities

This folder contains shared utility functions that are used across multiple FastTrackStudio scripts.

## Available Utility Libraries

- **GUI_Functions.lua**: Common functions for ReaImGUI based user interfaces
- **REAPER_Functions.lua**: General REAPER utility functions (extension checks, version comparison, etc.)
- **Serialize_Table.lua**: Functions for saving and loading tables to/from ExtState
- **Chunk_Functions.lua**: Functions for working with REAPER track/project chunks
- **General_Functions.lua**: Miscellaneous utility functions
- **theme.lua**: Theme-related functions for consistent UI appearance

## Usage

To use these shared utilities in your script, you need to:

1. First, get the path to the utils folder:

```lua
-- Get script path
local info = debug.getinfo(1, "S")
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])

-- Get the path to the FastTrackStudio Scripts root folder (two levels up)
local root_path = script_path:match("(.*[/\\])Tracks[/\\].*[/\\]")
if not root_path then
    root_path = script_path:match("(.*[/\\]).*[/\\].*[/\\]")
end
```

2. Load the utility modules:

```lua
-- Load the utility files you need
dofile(root_path .. "utils/Serialize Table.lua")
local GUI = dofile(root_path .. "utils/GUI_Functions.lua")
```

3. Use the functions:

```lua
-- Example of using GUI functions
function DrawUI()
    -- Use a tooltip
    if Configs.ToolTips then
        GUI.ToolTip(ctx, "This is a tooltip")
    end
end
```

## Adding New Functions

When adding new utility functions, please:

1. Place them in the appropriate file based on their functionality
2. Make sure they are properly documented
3. If appropriate, update the function to accept the ImGui context as a parameter to make it more reusable
4. Update any scripts that might benefit from using the new utility

## Benefits

Using shared utilities provides several benefits:

- **Consistency**: All scripts use the same implementation of common functions
- **Maintainability**: Bug fixes and improvements can be made in one place
- **Efficiency**: Reduces duplicate code across scripts
- **Collaboration**: Makes it easier for multiple developers to work on the codebase
