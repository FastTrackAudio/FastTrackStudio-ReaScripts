--[[ 
 * ReaScript Name: Insert media files as item on existing similarly named tracks or and new tracks (parent track prefix support)
 * Screenshot: https://i.imgur.com/TjrAYUz.gif
 * Author: X-Raym
 * Author URI: https://www.extremraym.com
 * Repository: X-Raym Premium Scripts
 * Licence: GPL v3
 * REAPER: 5.0
 * Version: 1.5.0
--]]

--[[ 
 * Changelog:
 * v1.5.0 (2023-05-16)
  + User Input
  + Sort files import under one parent
  + Create parent if missing
  # Select new track instead
  # Select new items
 * v1.4.2 (2023-05-14)
  + Warning if parent and no import
  # insert at bottom if no parent and track not found
 * v1.4.1 (2022-11-29)
  # Attempt to fix items moved after import
 * v1.4 (2022-11-29)
  # Better import if pattern has filter
  # Better import on new tracks (https://i.imgur.com/8vsERAG.gif)
  # Better import on existing tracks
 * v1.3.1 (2022-11-25)
  # MessageBox instead of Console for missing js_reascriptAPI
 * v1.3 (2021-03-01)
  + Preset file support
 * v1.2.3 (2019-10-07)
  + Possibility to have an filter pattern
 * v1.2.2 (2019-10-06)
  + Missing dependency warning
 * v1.2.1 (2019-09-30)
  + Special characters in parent
 * v1.2 (2019-09-30)
  + Parent: insert as direct sub
  + parent prefix customizable
 * v1.1 (2019-09-26)
  + parent track pattern
 * v1.0 (2019-09-26)
  + Initial Release
--]]

-----------------------------------------------------------
-- USER CONFIG AREA --
-----------------------------------------------------------

console = true
popup = true -- User input dialog box

vars = vars or {}
vars.parent_prefix = vars.parent_prefix or parent_prefix or "+"
vars.parent_suffix = vars.parent_suffix or parent_suffix or "+"
vars.pre_filter = '' -- pre filter file pattern to ignore. _(.+) for a prefix for eg.

input_title = "Import media files"
undo_text = "Insert media files as item on existing similarly named tracks or and new tracks (parent track prefix support)"

track_configs = {
    Reference = {
        patterns = {"print", "master", "smart tempo multitrack"},
        parent_track = "REF TRACK",
        default_track = "REF TRACK",
        insert_mode = "increment",
        increment_start = 1
    },
    Synth = {
        patterns = {"synth", "nord", "casio", "fa06", "charang", "briteness"},
        parent_track = "SYNTHS",
        default_track = "SY",
        insert_mode = "increment",
        increment_start = 1,
        create_if_missing = true
    },
    HiHat = {
        patterns = {"hi hat", "hihat", "hi%-hat", "hh", "hat"},
        parent_track = "CYMBALS BUS",
        default_track = "HiHat",
        insert_mode = "increment",
        negative_patterns = {"oh", "overhead"},  -- Don't match OH Hat
        sub_routes = {
            {
                patterns = {"close rm", "mid rm", "far rm"},
                parent_track = "ROOM BUS",
                default_track = "Rooms",
                insert_mode = "increment"
            }
        }
    },
    BGV = {
        patterns = {"bgv", "backing vocal", "background vocal", "bgv%d+", "harm"},  -- Added harm
        parent_track = "V BGVs",
        default_track = "BGV",
        insert_mode = "increment",
        increment_start = 1,
        extract_number = true,
        create_if_missing = true,
        negative_patterns = {"gtr harm", "guitar harm"},  -- Don't match guitar harmonies
        sub_routes = {
            {
                patterns = {"melody"},
                track = "V BGV Melody L",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"oct"},
                track = "V BGV Oct Up",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"soprano"},
                track = "V BGV Soprano L",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"alto"},
                track = "V BGV Alto L",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"tenor"},
                track = "V BGV Tenor L",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"baritone", "bari"},
                track = "V BGV Baritone L",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"bass"},
                track = "V BGV Bass L",
                insert_mode = "increment",
                increment_start = 1
            }
        }
    },
    Guitar = {
        patterns = {"guitar", "gtr"},
        parent_track = "GTR ELEC",
        default_track = "GTR E",
        insert_mode = "increment",
        increment_start = 1,
        stereo_pair = {
            enabled = true,
            patterns = {
                left = {"left", "_l[%s_]"},
                right = {"right", "_r[%s_]"},
                center = {"center", "_c[%s_]"}
            },
            naming = {
                format = "%s %d %s", -- track, number, side
                sides = {
                    left = "L",
                    right = "R",
                    center = "C"
                }
            }
        }
    },
    Keys = {
        patterns = {"keys", "piano", "pno", "nord", "rhodes", "wurli"},
        parent_track = "KEYS",
        default_track = "Keys",
        insert_mode = "increment",
        increment_start = 1,
        create_if_missing = true,
        force_child = true,
        never_match_parent = true,
        sub_routes = {
            {
                patterns = {"piano", "pno"},
                track = "PNO Grand",
                insert_mode = "increment"
            },
            {
                patterns = {"rhodes"},
                track = "PNO E Rhodes",
                insert_mode = "increment"
            },
            {
                patterns = {"wurli"},
                track = "PNO E Wurli",
                insert_mode = "increment"
            }
        }
    },
    Percussion = {
        patterns = {"perc"},
        parent_track = "PERC",
        default_track = "PERC",
        insert_mode = "increment",
        increment_start = 1
    },
    Room = {
        patterns = {"room", "rooms", "rm", "crotch", "mono u47", "mono"},
        parent_track = "ROOM BUS",
        default_track = "Rooms",
        insert_mode = "increment",
        increment_start = 1,
        negative_patterns = {"guitar", "gtr", "keys", "synth", "piano", "pno", "vocal", "vox", "harm"},  -- Added harm
        sub_routes = {
            {
                patterns = {"far"},
                track = "Room Far",
                insert_mode = "existing"
            },
            {
                patterns = {"oh", "overhead"},
                track = "Rooms L",
                insert_mode = "existing"
            },
            {
                patterns = {"ride"},
                track = "Rooms R",
                insert_mode = "existing"
            }
        },
        source_patterns = {
            {"snare", "snr"},
            {"kick", "kik"},
            {"hihat", "hi hat", "hi%-hat", "hh", "hat"},
            {"tom", "rack", "floor"},
            {"overhead", "oh"},
            {"ride"}
        },
        source_names = {
            ["hihat"] = "HiHat",
            ["hi hat"] = "HiHat",
            ["hi%-hat"] = "HiHat",
            ["hat"] = "HiHat",
            ["hh"] = "HiHat",
            ["snare"] = "Snare",
            ["snr"] = "Snare",
            ["kick"] = "Kick",
            ["kik"] = "Kick",
            ["tom"] = "Tom",
            ["rack"] = "Rack",
            ["floor"] = "Floor",
            ["overhead"] = "OH",
            ["oh"] = "OH",
            ["ride"] = "Ride"
        }
    },
    Overheads = {
        patterns = {"oh", "overhead", "oh hat", "oh ride"},
        parent_track = "CYMBALS BUS",
        default_track = "OH",
        insert_mode = "increment",
        increment_start = 1,
        priority = 2,
        sub_routes = {
            {
                patterns = {"hat", "oh hat"},
                track = "OH",
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"ride", "oh ride"},
                track = "OH",
                insert_mode = "increment",
                increment_start = 1
            }
        }
    },
    Toms = {
        patterns = {"tom", "rack", "floor"},
        parent_track = "TOMS",
        default_track = "Tom",
        insert_mode = "increment",
        increment_start = 1,
        create_if_missing = true,
        negative_patterns = {"bottom", "smart tempo"},
        sub_routes = {
            {
                patterns = {"rack"},
                track = "Tom 1",
                insert_mode = "existing",
                priority = 2
            },
            {
                patterns = {"floor"},
                track = "Tom 3",
                insert_mode = "existing",
                priority = 2
            },
            {
                patterns = {"room"},
                parent_track = "ROOM BUS",
                default_track = "Rooms",
                insert_mode = "increment"
            }
        }
    },
    Kick = {
        patterns = {"kick", "kik"},
        parent_track = "KICK SUM",
        default_track = "Kick",
        insert_mode = "increment",
        increment_start = 1,
        negative_patterns = {"kickler"},
        sub_routes = {
            {
                patterns = {"sub", "sub kick"},
                track = "Sub Kick",
                parent_track = "KICK BUS",
                insert_mode = "existing",
                priority = 2
            },
            {
                patterns = {"in"},
                track = "Kick In",
                insert_mode = "increment"
            },
            {
                patterns = {"out"},
                track = "Kick Out",
                insert_mode = "increment"
            },
            {
                patterns = {"trig", "sample", "trigger"},
                track = "Kick Trig",
                insert_mode = "increment"
            },
            {
                patterns = {"room"},
                parent_track = "ROOM BUS",
                default_track = "Rooms",
                insert_mode = "increment"
            }
        }
    },
    Snare = {
        patterns = {"snare", "snr"},
        parent_track = "SNARE SUM",
        default_track = "Snare",
        insert_mode = "increment",
        increment_start = 1,
        sub_routes = {
            {
                patterns = {"top"},
                track = "Snare Top",
                insert_mode = "increment",
                priority = 1
            },
            {
                patterns = {"bottom", "btm", "bot"},
                track = "Snare Bottom",
                insert_mode = "increment",
                priority = 1
            },
            {
                patterns = {"sample", "trig", "trigger"},
                track = "Snare Trig",
                insert_mode = "increment",
                priority = 1
            },
            {
                patterns = {"room"},
                parent_track = "ROOM BUS",
                default_track = "Rooms",
                insert_mode = "increment",
                priority = 1
            }
        }
    },
    Bass = {
        patterns = {"bass"},
        parent_track = "BASS",
        default_track = "Bass",
        insert_mode = "existing",
        sub_routes = {
            {
                patterns = {"di", "clean"},
                track = "Bass Clean",
                insert_mode = "existing"
            },
            {
                patterns = {"crunch", "drive"},
                track = "Bass Crunch",
                insert_mode = "existing"
            },
            {
                patterns = {"grit"},
                track = "Bass Grit",
                insert_mode = "existing"
            },
            {
                patterns = {"mic"},
                track = "Bass",
                insert_mode = "increment",
                increment_start = 1
            }
        }
    },
    LeadVocal = {
        patterns = {"vocal", "vox", "lead vox"},
        parent_track = "VOCALS",
        default_track = "V LEAD",
        insert_mode = "existing",
        negative_patterns = {"eko", "plate", "magic", "h3000", "bgv"}
    },
    VocalEffects = {
        patterns = {"h3000", "eko", "plate", "magic"},
        parent_track = "Vox FX",
        default_track = "V Room",
        insert_mode = "existing",
        sub_routes = {
            {
                patterns = {"plate", "eko"},
                track = "V Plate",
                insert_mode = "existing"
            },
            {
                patterns = {"h3000"},
                track = "Special 1",
                insert_mode = "existing"
            },
            {
                patterns = {"magic"},
                track = "Special 2",
                insert_mode = "existing"
            }
        }
    },
    PrintedFX = {
        patterns = {"h3000", "hall", "plate", "verb", "eko", "magic", "fx", "effect", "delay", "reverb"},
        parent_track = "PRINTED FX",
        default_track = "FX",
        insert_mode = "increment",
        increment_start = 1,
        is_printed_fx = true  -- Special flag for printed FX
    },
    Ride = {
        patterns = {"ride"},
        parent_track = "CYMBALS BUS",
        default_track = "Ride",
        insert_mode = "increment",
        negative_patterns = {"oh", "overhead"},  -- Don't match OH Ride
        sub_routes = {
            {
                patterns = {"close rm", "mid rm", "far rm"},
                parent_track = "ROOM BUS",
                default_track = "Rooms",
                insert_mode = "increment"
            }
        }
    },
    JaredVox = {
        patterns = {"jared"},
        parent_track = "VOCALS",
        default_track = "V LEAD",
        insert_mode = "increment",
        increment_start = 1,
        sub_routes = {
            {
                patterns = {"harm"},
                parent_track = "V BGVs",  -- Changed parent track for harmonies
                track = "V BGV",  -- Changed track name
                insert_mode = "increment",
                increment_start = 1
            },
            {
                patterns = {"call back"},
                track = "V LEAD 2",
                insert_mode = "increment"
            }
        }
    }
}

-----------------------------------------------------------
                              -- END OF USER CONFIG AREA --
-----------------------------------------------------------

-----------------------------------------------------------
-- GLOBALS --
-----------------------------------------------------------

vars_order = {"parent_prefix", "parent_suffix", "pre_filter"}

instructions = instructions or {}
instructions.parent_prefix = "Parent prefix? (characters)"
instructions.parent_suffix = "Parent suffix? (characters)"
instructions.pre_filter = "Pre-filter? (pattern)"

sep = "\n"
extrawidth = "extrawidth=120"
separator = "separator=" .. sep

ext_name = "XR_InsertMediaFilesNamedTrackParent"

if not reaper.JS_Dialog_BrowseForOpenFiles then
  reaper.MB("Missing dependency:\nPlease install js_reascriptAPI REAPER extension available from reapack. See Reapack.com for more infos.", "Error", 0)
  return
end

-----------------------------------------------------------
-- DEBUGGING --
-----------------------------------------------------------

function Msg(msg)
  reaper.ShowConsoleMsg(tostring(msg).."\n")
end

-----------------------------------------------------------
-- STATES --
-----------------------------------------------------------
function SaveState()
  for k, v in pairs( vars ) do
    reaper.SetExtState( ext_name, k, tostring(v), true )
  end
end

function GetExtState( var, val )
  local t = type( val )
  if reaper.HasExtState( ext_name, var ) then
    val = reaper.GetExtState( ext_name, var )
  end
  if t == "boolean" then val = toboolean( val )
  elseif t == "number" then val = tonumber( val )
  else
  end
  return val
end

function GetValsFromExtState()
  for k, v in pairs( vars ) do
    vars[k] = GetExtState( k, vars[k] )
  end
end

function ConcatenateVarsVals(t, sep, vars_order)
  local vals = {}
  for i, v in ipairs( vars_order ) do
    vals[i] = t[v]
  end
  return table.concat(vals, sep)
end

function ParseRetvalCSV( retvals_csv, sep, vars_order )
  local t = {}
  local i = 0
  for line in retvals_csv:gmatch("[^" .. sep .. "]*") do
  i = i + 1
  t[vars_order[i]] = line
  end
  return t
end

function ValidateVals( vars, vars_order )
  local validate = true
  for i, v in ipairs( vars_order ) do
    if vars[v] == nil then
      validate = false
      break
    end
  end
  return validate
end

-- SAVE TRACK SELECTION
function SaveSelectedTracks(table)
  for i = 0, reaper.CountSelectedTracks(0)-1 do
    table[i+1] = reaper.GetSelectedTrack(0, i)
  end
end

-- RESTORE TRACK SELECTION
function RestoreSelectedTracks(table)
  reaper.Main_OnCommand( 40297, 0 )
  for _, track in ipairs(table) do
    reaper.SetTrackSelected(track, true)
  end
end

function RestoreSelectedItems( items )
  reaper.SelectAllMediaItems(0, false)
  for i, item in ipairs( items ) do
    reaper.SetMediaItemSelected( item, true )
  end
end

-- SAVE INITIAL VIEW
function SaveView()
  start_time_view, end_time_view = reaper.BR_GetArrangeView(0)
end
-- RESTORE INITIAL VIEW
function RestoreView()
  reaper.BR_SetArrangeView(0, start_time_view, end_time_view)
end

function GetTracksNames()
    local tracks = {}
    local track_hierarchy = {}
    local parent_tracks = {}
    local folder_tracks = {}  -- New table to track folder tracks

    local count_tracks = reaper.CountTracks(0)
    for i = 0, count_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local retval, track_name = reaper.GetTrackName(track)
        local track_name_lower = track_name:lower()
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        -- Debugging output for existing track names
        reaper.ShowConsoleMsg("Existing track: " .. track_name .. "\n")

        -- Store track in main lookup
        tracks[track_name_lower] = track

        -- If this is a folder track (depth == 1), store it as a potential parent
        if depth == 1 then
            parent_tracks[track_name_lower] = track
            track_hierarchy[track_name_lower] = {
                track = track,
                children = {}
            }
            folder_tracks[track_name_lower] = true  -- Mark as folder track
        end
    end

    -- Store the hierarchies for later use
    tracks._parent_tracks = parent_tracks
    tracks._hierarchy = track_hierarchy
    tracks._folder_tracks = folder_tracks  -- Store folder tracks lookup
    return tracks
end

-- Split file name
function SplitFileName(strfilename)
    -- Returns the Path, Filename, and Extension as 3 values
    local path = string.match(strfilename, "(.+[\\/])")
    local file = string.match(strfilename, "[\\/]([^\\/%.]*)%.")
    local ext = string.match(strfilename, "%.([^\\/%.]*)$")
    
    if not path then path = "" end
    if not file then file = strfilename end
    if not ext then ext = "" end
    
    return path, file, ext
end

function CountChildTrack( track )

  local count = 0

  local depth = reaper.GetTrackDepth( track )
  local track_index = reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER')

  local count_tracks = reaper.CountTracks(0)
  for i = track_index, count_tracks-1 do
    local tr = reaper.GetTrack(0,i)
    if reaper.GetTrackDepth( tr ) > depth then count = count + 1 else break end
  end

  return count
end

function ReverseTable(t)
  local out = {}
  for k, v in ipairs(t) do
    out[#t + 1 - k] = v
  end
  return out
end

function CountFilesByName(files, name)
  local count = 0
  for _, file in ipairs(files) do
    if file.name:lower() == name:lower() then
      count = count + 1
    end
  end
  return count
end

-----------------------------------------------------------
-- MATCHING LOGIC --
-----------------------------------------------------------

function matchesTrackConfig(file_name, config)
    local name_lower = file_name:lower():gsub("-", "")  -- Normalize by removing dashes

    -- Check for negative matches
    for _, neg in ipairs(config.negative_matches) do
        if name_lower:find(neg:lower()) then
            return false
        end
    end

    -- Check for positive matches
    for _, name in ipairs(config.names) do
        if name_lower:find(name:lower():gsub("-", "")) then  -- Normalize by removing dashes
            return true
        end
    end

    -- Additional check for partial matches with "In" or "Out"
    if name_lower:find("in") or name_lower:find("out") then
        for _, name in ipairs(config.names) do
            if name_lower:find(name:lower():gsub("-", "")) then  -- Normalize by removing dashes
                return true
            end
        end
    end

    return false
end

-- Add before Main() function
local VALID_AUDIO_EXTENSIONS = {
    [".wav"] = true,
    [".mp3"] = true,
    [".aif"] = true,
    [".aiff"] = true,
    [".flac"] = true,
    [".ogg"] = true,
    [".m4a"] = true,
    [".wma"] = true
}

function isAudioFile(filename)
    local ext = string.match(filename:lower(), "%.%w+$")
    return ext and VALID_AUDIO_EXTENSIONS[ext] or false
end

function detectStereoSuffix(filename)
    local patterns = {
        {pattern = "left", suffix = "L"},
        {pattern = "right", suffix = "R"},
        {pattern = "center", suffix = "C"},
        {pattern = "_l[%s_]", suffix = "L"},
        {pattern = "_r[%s_]", suffix = "R"},
        {pattern = "_c[%s_]", suffix = "C"}
    }
    
    for _, p in ipairs(patterns) do
        if filename:lower():match(p.pattern) then
            return p.suffix
        end
    end
    return nil
end

-- Add this helper function to extract numbers closest to a pattern
function extractNumberNearPattern(filename, pattern)
    -- Find the pattern in the filename
    local pattern_start = filename:lower():find(pattern:lower())
    if not pattern_start then return nil end
    
    -- Look for numbers near the pattern (both before and after)
    local best_number = nil
    local best_score = -math.huge
    
    -- Find all numbers in the filename
    for number in filename:gmatch("%d+") do
        local num_start = filename:find(number)
        local distance = math.abs(num_start - pattern_start)
        
        -- Calculate score based on distance and separator type
        local score = -distance  -- Base score is negative distance (closer is better)
        
        -- Check what's between the pattern and number
        local between_text
        if num_start < pattern_start then
            between_text = filename:sub(num_start + #number, pattern_start - 1)
        else
            between_text = filename:sub(pattern_start + #pattern, num_start - 1)
        end
        
        -- Adjust score based on separator type and position
        if between_text:match("^%s*$") then  -- Just spaces
            score = score + 2000  -- Highest priority
        elseif between_text:match("^[%s_-]*$") then  -- Spaces, underscores, or hyphens
            score = score + 1500
        elseif between_text:match("^[%s_%.%-]*$") then  -- Spaces, underscores, dots, or hyphens
            score = score + 1000
        end
        
        -- Give higher priority to numbers that come after the pattern
        if num_start > pattern_start then
            score = score + 3000
        end
        
        -- Give lower priority to numbers at the start of the filename
        if num_start == 1 then
            score = score - 5000
        end
        
        -- Give lower priority to larger numbers (assuming track numbers are usually small)
        if tonumber(number) > 100 then
            score = score - 1000
        end
        
        if score > best_score then
            best_score = score
            best_number = tonumber(number)
        end
    end
    
    return best_number
end

-- Update getTrackForFile function to handle number extraction and stereo ordering
function getTrackForFile(file_name)
    local lower_name = file_name:lower()
    
    -- First check for Room matches (highest priority)
    local room_config = track_configs.Room
    if room_config then
        local matches_room = false
        local source_type = nil
        
        -- First check if it's a room mic
        for _, pattern in ipairs(room_config.patterns) do
            if lower_name:match(pattern) then
                matches_room = true
                break
            end
        end
        
        if matches_room then
            -- Check negative patterns
            local skip = false
            if room_config.negative_patterns then
                for _, neg_pattern in ipairs(room_config.negative_patterns) do
                    if lower_name:match(neg_pattern) then
                        skip = true
                        break
                    end
                end
            end
            
            if not skip then
                -- Try to identify the source
                for _, patterns in ipairs(room_config.source_patterns) do
                    for _, pattern in ipairs(patterns) do
                        if lower_name:match(pattern) then
                            source_type = room_config.source_names[pattern] or pattern:gsub("^%l", string.upper)
                            break
                        end
                    end
                    if source_type then break end
                end
                
                -- Create track name with source if found
                local track_name = room_config.default_track
                if source_type then
                    track_name = track_name .. " (" .. source_type .. ")"
                end
                
                return {
                    parent_track = room_config.parent_track,
                    default_track = track_name,
                    insert_mode = room_config.insert_mode,
                    increment_start = room_config.increment_start,
                    create_if_missing = room_config.create_if_missing,
                    is_bus = room_config.parent_track:match("BUS$") ~= nil
                }
            end
        end
    end
    
    -- Then check other configs
    for config_name, config in pairs(track_configs) do
        if config_name == "Room" then goto continue end  -- Skip Room config as we already checked it
        
        -- Check negative patterns first
        local skip = false
        if config.negative_patterns then
            for _, pattern in ipairs(config.negative_patterns) do
                if lower_name:match(pattern) then
                    skip = true
                    break
                end
            end
        end
        if skip then goto continue end
        
        -- Check if file matches any of the main patterns
        local matches = false
        local matching_pattern = nil
        for _, pattern in ipairs(config.patterns) do
            if lower_name:match(pattern) then
                matches = true
                matching_pattern = pattern
                break
            end
        end
        
        if matches then
            -- Check sub_routes first
            local matched_sub_route = false
            local best_sub_route = nil
            local best_priority = -1
            
            if config.sub_routes then
                for _, sub_route in ipairs(config.sub_routes) do
                    for _, pattern in ipairs(sub_route.patterns) do
                        if lower_name:match(pattern) then
                            matched_sub_route = true
                            local priority = sub_route.priority or 0
                            if priority > best_priority then
                                best_priority = priority
                                best_sub_route = sub_route
                            end
                        end
                    end
                end
                
                if best_sub_route then
                    -- Create track name with source type in parentheses
                    local track_name = best_sub_route.track
                    if best_sub_route.parent_track then
                        -- If sub-route has its own parent track (like Room), use base name with source type
                        if best_sub_route.default_track then
                            track_name = best_sub_route.default_track .. " (" .. config_name:gsub("^%l", string.upper) .. ")"
                        end
                    else
                        -- For regular sub-routes, use the track name as is without appending source type
                        track_name = best_sub_route.track
                    end
                    return {
                        parent_track = best_sub_route.parent_track or config.parent_track,
                        default_track = track_name,
                        insert_mode = best_sub_route.insert_mode,
                        create_if_missing = best_sub_route.create_if_missing,
                        is_bus = (best_sub_route.parent_track or config.parent_track):match("BUS$") ~= nil
                    }
                end
            end
            
            -- If we have sub_routes but none matched, or if never_match_parent is true,
            -- force increment mode and create a new track
            if (config.sub_routes and not matched_sub_route) or config.never_match_parent then
                return {
                    parent_track = config.parent_track,
                    default_track = config.default_track,
                    insert_mode = "increment",
                    increment_start = config.increment_start or 1,
                    create_if_missing = true,
                    force_child = true,
                    is_bus = config.parent_track:match("BUS$") ~= nil
                }
            end
            
            -- Return default config if no special cases match
            return {
                parent_track = config.parent_track,
                default_track = config.default_track,
                insert_mode = config.insert_mode,
                increment_start = config.increment_start,
                create_if_missing = config.create_if_missing,
                is_bus = config.parent_track:match("BUS$") ~= nil
            }
        end
        
        ::continue::
    end
    
    return nil
end

function LogTrackHierarchy()
    reaper.ShowConsoleMsg("\nTrack Hierarchy:\n")
    reaper.ShowConsoleMsg("------------------\n")
    
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        local _, name = reaper.GetTrackName(track)
        local indent = string.rep("  ", depth > 0 and depth or 0)
        reaper.ShowConsoleMsg(string.format("%s%s (Depth: %d)\n", indent, name, depth))
    end
    reaper.ShowConsoleMsg("------------------\n")
end

function LogTrackHierarchyWithNumbers()
    reaper.ShowConsoleMsg("\nTrack Hierarchy:\n")
    reaper.ShowConsoleMsg("------------------\n")
    
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        local _, name = reaper.GetTrackName(track)
        local indent = string.rep("  ", depth > 0 and depth or 0)
        reaper.ShowConsoleMsg(string.format("%s%s (Track: %d, Depth: %d)\n", indent, name, i, depth))
    end
    reaper.ShowConsoleMsg("------------------\n")
end

function FixFolderDepths()
    local current_depth = 0
    local last_track_idx = reaper.CountTracks(0) - 1
    
    for i = 0, last_track_idx do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        
        if depth == 1 then
            current_depth = current_depth + 1
        elseif depth < 0 then
            current_depth = current_depth + depth
        end
        
        -- If we're at a regular track (depth = 0)
        if depth == 0 then
            -- Check if we need to close a folder
            local next_track = i < last_track_idx and reaper.GetTrack(0, i + 1)
            if next_track then
                local next_depth = reaper.GetMediaTrackInfo_Value(next_track, "I_FOLDERDEPTH")
                -- If next track is a folder or we're at the end
                if next_depth == 1 or i == last_track_idx then
                    reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", -current_depth)
                    current_depth = 0
                end
            else
                -- Last track in project
                reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", -current_depth)
                current_depth = 0
            end
        end
    end
end

function GetTrackDepthInfo(track)
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local _, name = reaper.GetTrackName(track)
    return {
        track = track,
        depth = depth,
        name = name
    }
end

function SaveTrackStructure()
    local structure = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        table.insert(structure, GetTrackDepthInfo(track))
    end
    return structure
end

function RestoreTrackStructure(structure)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if structure[i + 1] then
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", structure[i + 1].depth)
        end
    end
end

-- Replace the track creation functions with these more precise versions
function CreateParentTrack(parent_name)
    -- Get the count before insertion
    local track_count = reaper.CountTracks(0)
    
    -- Create the new track at the end
    reaper.InsertTrackAtIndex(track_count, true)
    local parent_track = reaper.GetTrack(0, track_count)
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", parent_name, true)
    
    -- Make it a folder only if it's a new parent track at the end
    if track_count == reaper.CountTracks(0) - 1 then
        reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    end
    
    return parent_track
end

function CreateTrackUnderParent(parent_track, track_name)
    -- Get parent track index
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    local insert_idx = parent_idx + 1
    
    -- Find the last track in this folder level without modifying any depths
    local current_depth = 1
    for i = parent_idx + 1, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        
        if depth < 0 then
            current_depth = current_depth + depth
            if current_depth <= 0 then
                insert_idx = i
                break
            end
        elseif depth > 0 then
            current_depth = current_depth + depth
        end
    end
    
    -- Insert the new track
    reaper.InsertTrackAtIndex(insert_idx, true)
    local new_track = reaper.GetTrack(0, insert_idx)
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    
    -- Make sure track is visible
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 1)  -- Show in TCP
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 1)  -- Show in Mixer
    
    -- Only set folder depth if it's the last track in the project
    if insert_idx == reaper.CountTracks(0) - 1 then
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
    end
    
    return new_track
end

function Main()
    reaper.Undo_BeginBlock()

    parent_prefix = vars.parent_prefix
    parent_suffix = vars.parent_suffix
    pre_filter = vars.pre_filter

    retval, fileNames = reaper.JS_Dialog_BrowseForOpenFiles("Import media", "", "", "", true)

    if retval and retval > 0 then
        -- Store initial cursor position
        local initial_cursor_pos = reaper.GetCursorPosition()
        
        reaper.SelectAllMediaItems(0, false)

        -- Get existing tracks BEFORE processing files
        tracks = GetTracksNames()

        files = {}
        folder = ''
        local i = 1
        local cur_pos = reaper.GetCursorPosition()  -- Store the current cursor position
        local not_sorted_folder = "NOT SORTED"  -- Default folder name for failed items
        local not_sorted_track = nil
        local failed_count = 0  -- Initialize counter
        local success_count = 0  -- Initialize counter
        local total_processed = 0  -- Track total files processed

        local used_tracks = {}  -- Track used tracks for all types
        local failed_files = {}  -- Track which files failed and why

        local stereo_pairs = {}  -- Track stereo pairs for ordering
        local files_to_process = {}  -- Store files for ordered processing

        -- First pass: collect all files and identify stereo pairs
        for file in fileNames:gmatch("[^\0]*") do
            if i > 1 then
                if not isAudioFile(file) then
                    reaper.ShowConsoleMsg("Skipping non-audio file: " .. file .. "\n")
                    goto continue_collect
                end
                
                local path, file_name, extension = SplitFileName(file)
                local track_config = getTrackForFile(file_name)
                
                table.insert(files_to_process, {
                    file = file,
                    name = file_name,
                    config = track_config
                })
                
                if track_config and track_config.stereo_side then
                    local base_name = track_config.default_track:gsub("%s+[LR]$", "")
                    stereo_pairs[base_name] = stereo_pairs[base_name] or {}
                    stereo_pairs[base_name][track_config.stereo_side] = #files_to_process
                end
            else
                folder = file
            end
            ::continue_collect::
            i = i + 1
        end

        -- Sort stereo pairs to ensure L comes before R
        for base_name, pair in pairs(stereo_pairs) do
            if pair.L and pair.R and files_to_process[pair.L].config.stereo_side == "R" then
                -- Swap the files
                files_to_process[pair.L], files_to_process[pair.R] = files_to_process[pair.R], files_to_process[pair.L]
            end
        end

        -- Process files in order
        for _, file_info in ipairs(files_to_process) do
            local file = file_info.file
            local file_name = file_info.name
            local track_config = file_info.config

            -- Debugging output
            reaper.ShowConsoleMsg("Processing file: " .. file_name .. "\n")

            if track_config then
                reaper.ShowConsoleMsg("Matched track config: " .. (track_config.parent_track or "No Parent Track") .. "\n")
                
                -- Skip Printed FX files for now, we'll handle them later
                if track_config.is_printed_fx then
                    goto continue_processing
                end

                -- Try to find parent track, create if missing
                local parent_track = tracks[track_config.parent_track:lower()]
                if not parent_track and track_config.parent_track then
                    parent_track = CreateParentTrack(track_config.parent_track)
                    tracks[track_config.parent_track:lower()] = parent_track
                end

                if parent_track then
                    -- Logic for placing the file in the correct track
                    local track_count = CountFilesByName(files, track_config.default_track)
                    local target_track_name = track_config.default_track

                    -- Handle different insert modes
                    if track_config.insert_mode == "increment" then
                        local base_name = track_config.default_track
                        
                        -- Use only the used_tracks counter for incrementing
                        if used_tracks[base_name] then
                            target_track_name = base_name .. " " .. used_tracks[base_name]
                            used_tracks[base_name] = used_tracks[base_name] + 1
                        else
                            target_track_name = base_name
                            used_tracks[base_name] = 1
                        end
                    end

                    -- Find or create the target track
                    local target_track = tracks[target_track_name:lower()]
                    -- Skip if the target track is a folder track
                    if target_track and tracks._folder_tracks[target_track_name:lower()] then
                        target_track = nil
                    end
                    
                    if not target_track and (track_config.create_if_missing or track_config.insert_mode == "increment") then
                        target_track = CreateTrackUnderParent(parent_track, target_track_name)
                        tracks[target_track_name:lower()] = target_track
                    end

                    if target_track then
                        reaper.SetOnlyTrackSelected(target_track)
                        reaper.SetEditCurPos(cur_pos, false, false)
                        reaper.InsertMedia(file, 0)
                        used_tracks[target_track_name] = (used_tracks[target_track_name] or 0) + 1
                        success_count = success_count + 1
                        total_processed = total_processed + 1
                        reaper.ShowConsoleMsg("Successfully placed file in track: " .. target_track_name .. "\n")
                    else
                        -- Handle failed placement
                        reaper.ShowConsoleMsg("Failed to place file: " .. file_name .. "\n")
                        table.insert(failed_files, {
                            name = file_name,
                            reason = "Could not create or find target track: " .. target_track_name
                        })
                        failed_count = failed_count + 1
                        total_processed = total_processed + 1
                        -- Place in NOT SORTED
                        if not not_sorted_track then
                            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                            not_sorted_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                            reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", not_sorted_folder, true)
                            reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)  -- Make it a folder
                        end
                        
                        -- Create a new track under NOT SORTED for this file
                        local unsorted_track = CreateTrackUnderParent(not_sorted_track, file_name)
                        reaper.SetOnlyTrackSelected(unsorted_track)
                        reaper.SetEditCurPos(cur_pos, false, false)
                        reaper.InsertMedia(file, 0)
                    end
                else
                    -- Handle missing parent track
                    reaper.ShowConsoleMsg("Parent track not found: " .. track_config.parent_track .. "\n")
                    table.insert(failed_files, {
                        name = file_name,
                        reason = "Parent track not found: " .. track_config.parent_track
                    })
                    failed_count = failed_count + 1
                    total_processed = total_processed + 1
                    -- Place in NOT SORTED
                    if not not_sorted_track then
                        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                        not_sorted_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                        reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", not_sorted_folder, true)
                        reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)  -- Make it a folder
                    end
                    
                    -- Create a new track under NOT SORTED for this file
                    local unsorted_track = CreateTrackUnderParent(not_sorted_track, file_name)
                    reaper.SetOnlyTrackSelected(unsorted_track)
                    reaper.SetEditCurPos(cur_pos, false, false)
                    reaper.InsertMedia(file, 0)
                end
            else
                -- Handle no matching config
                reaper.ShowConsoleMsg("No matching track config found for: " .. file_name .. "\n")
                table.insert(failed_files, {
                    name = file_name,
                    reason = "No matching track config found"
                })
                failed_count = failed_count + 1
                total_processed = total_processed + 1
                -- Place in NOT SORTED
                if not not_sorted_track then
                    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                    not_sorted_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                    reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", not_sorted_folder, true)
                    reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)  -- Make it a folder
                end
                
                -- Create a new track under NOT SORTED for this file
                local unsorted_track = CreateTrackUnderParent(not_sorted_track, file_name)
                reaper.SetOnlyTrackSelected(unsorted_track)
                reaper.SetEditCurPos(cur_pos, false, false)
                reaper.InsertMedia(file, 0)
            end

            ::continue_processing::
            table.insert(files, { path = folder .. file, name = file_name })
        end

        -- Now handle Printed FX files separately
        local printed_fx_files = {}
        for _, file_info in ipairs(files_to_process) do
            if file_info.config and file_info.config.is_printed_fx then
                table.insert(printed_fx_files, file_info)
            end
        end

        if #printed_fx_files > 0 then
            local printed_fx_track = CreateParentTrack("PRINTED FX")
            local fx_count = 0
            
            for _, file_info in ipairs(printed_fx_files) do
                local track_name = file_info.config.default_track
                if fx_count > 0 then
                    track_name = track_name .. " " .. fx_count
                end
                
                local track = CreateTrackUnderParent(printed_fx_track, track_name)
                reaper.SetOnlyTrackSelected(track)
                reaper.SetEditCurPos(cur_pos, false, false)
                reaper.InsertMedia(file_info.file, 0)
                fx_count = fx_count + 1
                success_count = success_count + 1
                total_processed = total_processed + 1
            end
        end

        -- Print summary
        reaper.ShowConsoleMsg("\nImport Summary:\n")
        reaper.ShowConsoleMsg("Successfully sorted items: " .. tostring(success_count) .. "\n")
        reaper.ShowConsoleMsg("Failed to sort items: " .. tostring(failed_count) .. "\n")
        reaper.ShowConsoleMsg("Total files processed: " .. tostring(total_processed) .. "\n")

        if #failed_files > 0 then
            reaper.ShowConsoleMsg("\nFailed Files Report:\n")
            for _, failure in ipairs(failed_files) do
                reaper.ShowConsoleMsg(string.format("File: %s\nReason: %s\n\n", failure.name, failure.reason))
            end
        end

        LogTrackHierarchy()
        
        -- Restore cursor position
        reaper.SetEditCurPos(initial_cursor_pos, false, false)
        
        reaper.Undo_EndBlock(undo_text, -1)
    end
end

-----------------------------------------------------------
-- EXECUTE --
-----------------------------------------------------------

Main()

