# Default Patterns and Groups System

This document explains how to use the default patterns and default groups system in the FTS Import Into Template By Name script.

## Overview

The default patterns and groups system allows you to:

1. Define standard patterns for track naming categories (tracking info, performers, arrangements, etc.)
2. Define standard group configurations (drums, guitars, vocals, etc.)
3. Choose how to inherit these defaults in your working configurations

## Default Patterns

Default patterns are stored globally and can be used across all your projects. They include:

- **Tracking Info**: Recording takes, comps, versions (e.g., `[Take 1]`, `[Master]`)
- **Subtype**: Type variations (e.g., `Clean`, `Distorted`)
- **Arrangement**: Arrangement parts (e.g., `Verse`, `Chorus`)
- **Performer**: Names (e.g., `(John)`, `(Mary)`)
- **Section**: Song sections (e.g., `A`, `B`, `Bridge`)
- **Layers**: Doubled parts (e.g., `Double`, `Layer`)
- **Mic**: Microphone types (e.g., `SM57`, `Room`, `OH`)
- **Playlist**: Take alternatives (e.g., `.1`, `.2`)
- **Type**: Track types (e.g., `BUS`, `SUM`, `MIDI`)

## Default Groups

Default groups define standard track configurations, including:

- Match patterns for identifying audio files
- Parent track structure
- Naming conventions
- Track template options
- Increment settings

## Inheritance Modes

For both patterns and groups, you can choose from three inheritance modes:

1. **Use Defaults Only**: Only the default patterns/groups are used. Any changes you make are not saved.
2. **Use Defaults + Overrides**: Default patterns/groups are used as a foundation, and your changes are saved as overrides.
3. **Use Overrides Only**: Only your custom patterns/groups are used, ignoring defaults.

## How to Use

### Managing Default Patterns

1. Go to the "Global Patterns" tab
2. Select your desired inheritance mode
3. Click "Edit Default Patterns" to modify the global defaults
4. Add and remove patterns for each category
5. Save your changes

### Managing Default Groups

1. Go to the "Track Configurations" tab
2. Select your desired inheritance mode
3. Click "Edit Default Groups" to modify the global defaults
4. Add and edit group configurations
5. Save your changes

### Importing/Exporting

When exporting configurations to JSON, both your overrides and the inheritance modes are saved. When importing, these settings are restored.

## JSON Structure

The default patterns and groups are stored in `defaults.json` with this structure:

```json
{
  "default_patterns": {
    "tracking": ["Take", "Comp", "Alt"],
    "subtype": ["Clean", "Distorted"],
    ...
  },
  "default_groups": [
    {
      "name": "Drums",
      "patterns": ["drum", "kick", "snare"],
      "parent_track": "DRUMS",
      ...
    },
    ...
  ]
}
```

## Tips

- Green text indicates default patterns/groups
- In "Use Defaults Only" mode, editing is disabled
- For maximum flexibility, use "Defaults + Overrides" mode
- For project-specific settings, use "Overrides Only" mode
