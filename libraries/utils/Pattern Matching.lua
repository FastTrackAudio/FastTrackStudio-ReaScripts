-- @noindex
--[[
 * FastTrackStudio - Pattern Matching Utility
 * Provides functions for advanced pattern matching used in import and naming scripts
 * This utility extracts pattern matching functionality from the original FTS_Import Into Template By Name script
 * and makes it reusable across multiple scripts
--]]

local PatternMatching = {}

-- Check if a string matches any pattern in a list
-- @param str The string to check
-- @param patterns Table of patterns to match against
-- @return boolean True if any pattern matches, false otherwise
-- @return string The matching pattern or nil
function PatternMatching.MatchesAnyPattern(str, patterns)
    if not str or not patterns then return false end
    
    local lower_str = str:lower()
    for _, pattern in ipairs(patterns) do
        -- Handle the # wildcard for numbers by replacing it with a digit pattern
        local search_pattern = pattern:gsub("#", "%%d+")
        
        -- Try to find the pattern in the string
        if lower_str:find(search_pattern:lower()) then
            return true, pattern
        end
    end
    
    return false
end

-- Check if a string matches any negative pattern (exclusion) in a list
-- @param str The string to check
-- @param negative_patterns Table of patterns to avoid matching
-- @return boolean True if any negative pattern matches, false otherwise
function PatternMatching.MatchesNegativePattern(str, negative_patterns)
    if not str or not negative_patterns then return false end
    
    local lower_str = str:lower()
    for _, pattern in ipairs(negative_patterns) do
        -- Handle the # wildcard for numbers by replacing it with a digit pattern
        local search_pattern = pattern:gsub("#", "%%d+")
        
        if lower_str:find(search_pattern:lower()) then
            return true
        end
    end
    
    return false
end

-- Extract a number from a file name based on a pattern
-- @param file_name The file name to extract from
-- @param pattern The pattern containing capturing groups for the number
-- @return number|nil The extracted number or nil if not found
function PatternMatching.ExtractNumber(file_name, pattern)
    if not file_name or not pattern then return nil end
    
    local lower_name = file_name:lower()
    local number_str = lower_name:match(pattern)
    
    if number_str then
        local number = tonumber(number_str)
        if number then
            return number
        end
    end
    
    return nil
end

-- Detect stereo pairs based on patterns (left/right/center)
-- @param file_name The file name to check
-- @param stereo_config Configuration table for stereo detection
-- @return table|nil Stereo information or nil if not a stereo file
function PatternMatching.DetectStereoPair(file_name, stereo_config)
    if not file_name or not stereo_config or not stereo_config.patterns then
        return nil
    end
    
    local lower_name = file_name:lower()
    local stereo_info = {is_stereo = false}
    
    -- Check for left channel
    for _, pattern in ipairs(stereo_config.patterns.left or {}) do
        if lower_name:match(pattern) then
            stereo_info.is_stereo = true
            stereo_info.side = "L"
            stereo_info.stereo_side = "L"
            break
        end
    end
    
    -- Check for right channel
    if not stereo_info.is_stereo then
        for _, pattern in ipairs(stereo_config.patterns.right or {}) do
            if lower_name:match(pattern) then
                stereo_info.is_stereo = true
                stereo_info.side = "R"
                stereo_info.stereo_side = "R"
                break
            end
        end
    end
    
    -- Check for center channel
    if not stereo_info.is_stereo then
        for _, pattern in ipairs(stereo_config.patterns.center or {}) do
            if lower_name:match(pattern) then
                stereo_info.is_stereo = true
                stereo_info.side = "C"
                stereo_info.stereo_side = "C"
                break
            end
        end
    end
    
    if stereo_info.is_stereo then
        -- Strip stereo identifiers from base name for pairing
        stereo_info.base_name = lower_name:gsub(stereo_info.side .. "[%s_]", "")
                                         :gsub("[%s_]" .. stereo_info.side, "")
                                         :gsub("left", "")
                                         :gsub("right", "")
                                         :gsub("center", "")
        return stereo_info
    end
    
    return nil
end

-- Find the best matching track configuration for a file
-- @param file_name The file name to match
-- @param track_configs Table of track configurations
-- @param context Optional context for matching (like parent track)
-- @return table|nil The matching track configuration or nil if no match
function PatternMatching.FindMatchingConfig(file_name, track_configs, context)
    if not file_name or not track_configs then return nil end
    
    local lower_name = file_name:lower()
    local best_match = nil
    local best_priority = -1
    
    for config_name, config in pairs(track_configs) do
        -- Skip if this config lacks patterns
        if not config.patterns then goto continue end
        
        -- Check negative patterns first (exclusions)
        local skip = false
        if config.negative_patterns then
            if PatternMatching.MatchesNegativePattern(lower_name, config.negative_patterns) then
                skip = true
            end
        end
        if skip then goto continue end
        
        -- Check if file matches any of the main patterns
        local matches, matching_pattern = PatternMatching.MatchesAnyPattern(lower_name, config.patterns)
        
        if matches then
            -- Check sub_routes first (they have higher priority)
            local matched_sub_route = false
            local best_sub_route = nil
            local sub_priority = -1
            
            if config.sub_routes then
                for _, sub_route in ipairs(config.sub_routes) do
                    local sub_matches = PatternMatching.MatchesAnyPattern(lower_name, sub_route.patterns or {})
                    if sub_matches then
                        matched_sub_route = true
                        local priority = sub_route.priority or 0
                        if priority > sub_priority then
                            sub_priority = priority
                            best_sub_route = sub_route
                        end
                    end
                end
                
                if best_sub_route then
                    -- Create a hybrid config with parent info and sub-route specifics
                    local result = {}
                    
                    -- Copy the sub-route
                    for k, v in pairs(best_sub_route) do
                        result[k] = v
                    end
                    
                    -- Use parent track from sub-route or main config
                    result.parent_track = best_sub_route.parent_track or config.parent_track
                    
                    -- If sub-route doesn't have default_track, use the one from main config
                    if not result.default_track and best_sub_route.track then
                        result.default_track = best_sub_route.track
                    end
                    
                    -- Copy pattern categories if available
                    result.pattern_categories = config.pattern_categories
                    
                    -- Inherit other properties from main config
                    result.is_bus = (result.parent_track or ""):match("BUS$") ~= nil
                    result.stereo_pair = config.stereo_pair
                    
                    -- Check priority
                    local match_priority = sub_priority + (config.priority or 0)
                    if match_priority > best_priority then
                        best_priority = match_priority
                        best_match = result
                    end
                    
                    goto continue
                end
            end
            
            -- If the main config should never match directly and sub-routes exist but none matched,
            -- skip this config
            if config.never_match_parent and config.sub_routes and not matched_sub_route then
                goto continue
            end
            
            -- Match to the main config
            local match_priority = config.priority or 0
            if match_priority >= best_priority then
                best_priority = match_priority
                
                -- Create a copy of the config for the result
                best_match = {}
                for k, v in pairs(config) do
                    best_match[k] = v
                end
                
                -- Add the matched pattern for reference
                best_match.matched_pattern = matching_pattern
            end
        end
        
        ::continue::
    end
    
    -- Process stereo information if needed
    if best_match and best_match.stereo_pair and best_match.stereo_pair.enabled then
        local stereo_info = PatternMatching.DetectStereoPair(file_name, best_match.stereo_pair)
        if stereo_info then
            best_match.stereo_side = stereo_info.side
            best_match.base_name = stereo_info.base_name
        end
    end
    
    -- Extract track number if configured
    if best_match and best_match.extract_number then
        local num_pattern = best_match.number_pattern or "(%d+)"
        local track_num = PatternMatching.ExtractNumber(file_name, num_pattern)
        if track_num then
            best_match.extracted_number = track_num
        end
    end
    
    return best_match
end

-- Generate an appropriate track name based on a configuration and file name
-- @param file_name The file name to base the track name on
-- @param config The track configuration
-- @param existing_tracks Optional table of existing track names
-- @return string The generated track name
function PatternMatching.GenerateTrackName(file_name, config, existing_tracks)
    if not file_name or not config then return file_name end
    
    -- Start with the default track name from the config
    local track_name = config.default_track or file_name
    
    -- Apply stereo naming if applicable
    if config.stereo_pair and config.stereo_pair.enabled and 
       config.stereo_side and config.stereo_pair.naming then
        
        local naming = config.stereo_pair.naming
        local side_label = naming.sides[config.stereo_side:lower()] or config.stereo_side
        
        -- Format the track name according to config
        if naming.format then
            local increment = config.increment_start or 1
            track_name = string.format(naming.format, track_name, increment, side_label)
        else
            -- Default format if none specified
            track_name = track_name .. " " .. side_label
        end
        
        return track_name
    end
    
    -- Check for advanced naming with pattern categories
    if config.pattern_categories then
        -- Extract components from the filename based on pattern categories
        local components = {
            prefix = "",
            tracking = "",
            subtype = "",
            arrangement = "",
            performer = "",
            section = "",
            layers = "",
            mic = "",
            playlist = "",
            type = ""  -- Add the new Type category
        }
        
        local file_name_lower = file_name:lower()
        
        -- Check each pattern category and extract matching information
        for category_key, category_data in pairs(config.pattern_categories) do
            if category_data and category_data.patterns and #category_data.patterns > 0 then
                for _, pattern in ipairs(category_data.patterns) do
                    -- Handle number wildcard (#)
                    local search_pattern = pattern:gsub("#", "%%d+")
                    
                    -- Check if filename contains this pattern
                    local match_start, match_end = file_name_lower:find(search_pattern:lower())
                    if match_start then
                        -- Extract the actual text from the original filename (preserving case)
                        local match_text = file_name:sub(match_start, match_end)
                        
                        -- Store this component
                        if components[category_key] == "" then
                            components[category_key] = match_text
                        else
                            -- If we already have a match for this category, pick the longer one
                            if #match_text > #components[category_key] then
                                components[category_key] = match_text
                            end
                        end
                    end
                end
            end
        end
        
        -- Build the track name according to the specified format:
        -- Prefix -> [TRACKING INFO] -> Subtype -> Arrangement -> (Performer) -> Section -> Layers -> Multi-Mic -> Playlist -> (Type)
        local parts = {}
        
        if components.prefix ~= "" then
            table.insert(parts, components.prefix)
        end
        
        if components.tracking ~= "" then
            table.insert(parts, "[" .. components.tracking .. "]")
        end
        
        if components.subtype ~= "" then
            table.insert(parts, components.subtype)
        end
        
        if components.arrangement ~= "" then
            table.insert(parts, components.arrangement)
        end
        
        if components.performer ~= "" then
            table.insert(parts, "(" .. components.performer .. ")")
        end
        
        if components.section ~= "" then
            table.insert(parts, components.section)
        end
        
        if components.layers ~= "" then
            table.insert(parts, components.layers)
        end
        
        if components.mic ~= "" then
            table.insert(parts, components.mic)
        end
        
        if components.playlist ~= "" then
            table.insert(parts, components.playlist)
        end
        
        -- Add the Type category if present (formatted with parentheses)
        if components.type ~= "" then
            -- Only add parentheses if they're not already there
            if not components.type:match("^%(.*%)$") then
                table.insert(parts, "(" .. components.type .. ")")
            else
                table.insert(parts, components.type)
            end
        end
        
        -- If we have at least one component, use our constructed name
        if #parts > 0 then
            track_name = table.concat(parts, " ")
        end
    end
    
    -- If we're using increment mode with existing tracks
    if config.insert_mode == "increment" and existing_tracks then
        local increment = config.increment_start or 1
        local candidate_name
        
        -- Increment until we find an unused name
        while true do
            if increment > 1 then
                candidate_name = track_name .. " " .. increment
            else
                candidate_name = track_name
            end
            
            -- Check if this name already exists
            local exists = false
            for _, existing_name in pairs(existing_tracks) do
                if existing_name == candidate_name then
                    exists = true
                    break
                end
            end
            
            if not exists then
                track_name = candidate_name
                break
            end
            
            increment = increment + 1
        end
    end
    
    -- If we have an extracted number, use it in the name
    if config.extracted_number and config.number_format then
        track_name = string.format(config.number_format, track_name, config.extracted_number)
    elseif config.extracted_number then
        track_name = track_name .. " " .. config.extracted_number
    end
    
    return track_name
end

-- Create a filtered version of a file name for matching
-- @param file_name The original file name
-- @param pre_filter Optional pattern to filter out from the file name
-- @return string The filtered file name for matching
function PatternMatching.CleanFileName(file_name, pre_filter)
    if not file_name then return "" end
    
    -- Extract just the file name without path and extension
    local name_only = file_name:match("([^\\/]+)%.%w+$") or file_name
    
    -- Apply pre-filter if provided
    if pre_filter and pre_filter ~= "" then
        name_only = name_only:gsub(pre_filter, "")
    end
    
    -- Normalize spaces, remove special characters
    name_only = name_only:gsub("_", " ")
                       :gsub("-", " ")
                       :gsub("%s+", " ")
                       :gsub("^%s", "")
                       :gsub("%s$", "")
    
    return name_only
end

-- Validate a track configuration to ensure it has all required fields
-- @param config The track configuration to validate
-- @return boolean True if valid, false otherwise
-- @return string Error message if invalid
function PatternMatching.ValidateConfig(config)
    if not config then
        return false, "Configuration is nil"
    end
    
    -- Check required fields
    if not config.name then
        return false, "Configuration missing 'name' field"
    end
    
    if not config.parent_track or config.parent_track == "" then
        return false, "Configuration missing 'parent_track' field"
    end
    
    if not config.default_track or config.default_track == "" then
        return false, "Configuration missing 'default_track' field"
    end
    
    if not config.patterns or #config.patterns == 0 then
        return false, "Configuration has no patterns defined"
    end
    
    -- Insert mode should be valid
    if config.insert_mode and config.insert_mode ~= "increment" and config.insert_mode ~= "existing" then
        return false, "Invalid 'insert_mode': " .. tostring(config.insert_mode)
    end
    
    -- Check pattern categories if present
    if config.pattern_categories then
        for category_key, category_data in pairs(config.pattern_categories) do
            if type(category_data) ~= "table" then
                return false, "Invalid pattern category data for '" .. category_key .. "'"
            end
            
            if category_data.required and (not category_data.patterns or #category_data.patterns == 0) then
                return false, "Required pattern category '" .. category_key .. "' has no patterns defined"
            end
        end
    end
    
    -- Check sub-routes if present
    if config.sub_routes then
        for i, sub_route in ipairs(config.sub_routes) do
            if not sub_route.patterns or #sub_route.patterns == 0 then
                return false, "Sub-route #" .. i .. " has no patterns defined"
            end
            
            if not sub_route.track and not sub_route.default_track then
                return false, "Sub-route #" .. i .. " has no track or default_track defined"
            end
        end
    end
    
    return true
end

-- Create a new track configuration with default values
-- @param name The name of the configuration
-- @return table A new track configuration
function PatternMatching.CreateNewConfig(name)
    return {
        name = name or "",
        patterns = {},
        negative_patterns = {},
        parent_track = "",
        default_track = "",
        insert_mode = "increment",
        increment_start = 1,
        create_if_missing = true,
        pattern_categories = {
            prefix = { patterns = {}, required = false },
            tracking = { patterns = {}, required = false },
            subtype = { patterns = {}, required = false },
            arrangement = { patterns = {}, required = false },
            performer = { patterns = {}, required = false },
            section = { patterns = {}, required = false },
            layers = { patterns = {}, required = false },
            mic = { patterns = {}, required = false },
            playlist = { patterns = {}, required = false }
        },
        sub_routes = {}
    }
end

-- Return the utility module
return PatternMatching 