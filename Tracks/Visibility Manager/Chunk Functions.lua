-- @noindex
function bfut_ResetAllChunkGuids(item_chunk, key)
    while item_chunk:match('%s('..key..')') do
        item_chunk = item_chunk:gsub('%s('..key..')%s+.-[\r]-[%\n]', "\ntemp%1 "..reaper.genGuid("").."\n", 1)
    end
    return item_chunk:gsub('temp'..key, key), true
end

function SubMagicChar(string)
    local string = string.gsub(string, '[%[%]%(%)%+%-%*%?%^%$%%]', '%%%1')
    return string
end
  
function ResetChunkIndentifier(chunk, key)
    for line in chunk:gmatch( '(.-)\n+') do
        if line:match(key) then
            local new_line = line:gsub(key.."%s+{.+}",key..' '..reaper.genGuid(""))
            line = SubMagicChar(line)
            chunk=string.gsub(chunk,line,new_line)
        end
    end
    return chunk
end


function ResetAllIndentifiers(chunk) -- Tested in Tracks. 
    -- Track
    chunk = ResetChunkIndentifier(chunk, 'TRACKID')
    chunk = ResetChunkIndentifier(chunk, 'FXID')
    -- Items
    chunk = ResetChunkIndentifier(chunk, 'GUID')
    chunk = ResetChunkIndentifier(chunk, 'IGUID')
    chunk = ResetChunkIndentifier(chunk, 'POOLEDEVTS')
    -- Envelopes
    chunk = ResetChunkIndentifier(chunk, 'EGUID')
    return chunk
end

function ResetTrackIndentifiers(track)
    local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
    local new_chunk = ResetAllIndentifiers(chunk)
    reaper.SetTrackStateChunk(track, new_chunk, false)
end

function GetChunkVal(chunk,key)
    return string.match(chunk,key..' '..'(.-)\n')
end

function GetChunkLine(chunk,key,idx) -- Basically GetChunkVal but return with the key 
    return string.match(chunk,key..' '..'.-\n',idx)
end

function ChangeChunkVal(chunk, key, new_value) -- Thanks Sexan 🐱
    local chunk_tbl = split_by_line(chunk)
    for i = 1, #chunk_tbl do
        if chunk_tbl[i]:match(key) then
            chunk_tbl[i] = key .. " " .. new_value
        end
    end
    return table.concat(chunk_tbl,'\n')
end

function literalizepercent(str)
    return str:gsub(
      "[%%]",
      function(c)
        return "%" .. c
      end
    )
end

function ChangeChunkVal2(chunk, key, new_value) -- probably faster ?
    local new_value = literalizepercent(tostring(new_value))
    while chunk:match('%s('..key..')') do
      chunk = chunk:gsub('%s('..key..')%s+.-[\r]-[%\n]', "\ntemp%1 "..new_value.."\n", 1)
    end
    return chunk:gsub('temp'..key, key), true
end

function string.starts(String,Start)
    return string.sub(String,1,string.len(Start))==Start
end

function split_by_line(str)
    local t = {}
    for line in string.gmatch(str, "[^\r\n]+") do
        t[#t + 1] = line
    end
    return t
end

function literalize(str)
    return str:gsub(
      "[%(%)%.%%%+%-%*%?%[%]%^%$]",
      function(c)
        return "%" .. c
      end
    )
end

function ChunkTableGetSection(chunk_lines,key) -- Thanks BirdBird! 🦜
    --GET ITEM CHUNKS
    local section_chunks = {}
    local last_section_chunk = -1
    local current_scope = 0
    local i = 1
    while i <= #chunk_lines do
        local line = chunk_lines[i]
        
        --MANAGE SCOPE
        local scope_end = false
        if line == '<'..key then       
            last_section_chunk = i
            current_scope = current_scope + 1
        elseif string.starts(line, '<') then
            current_scope = current_scope + 1
        elseif string.starts(line, '>') then
            current_scope = current_scope - 1
            scope_end = true
        end
        
        --GRAB ITEM CHUNKS
        if current_scope == 1 and last_section_chunk ~= -1 and scope_end then
            local s = ''
            for j = last_section_chunk, i do
                s = s .. chunk_lines[j] .. '\n'
            end
            last_section_chunk = -1
            table.insert(section_chunks, s)
        end
        i = i + 1
    end
  
    return section_chunks
 end

function GetChunkSection(key, chunk)
    local chunk_lines = split_by_line(chunk)
    local table_Section = ChunkTableGetSection(chunk_lines,key)
    local chunk_section = table.concat(table_Section)
    return chunk_section
end
  
function RemoveChunkSection(key, chunk)
    local chunk_lines = split_by_line(chunk)
    local table_Section = ChunkTableGetSection(chunk_lines,key)
    local old_chunk_Section = table.concat(table_Section)
    local chunk_without_key_Section = string.gsub(chunk,literalize(old_chunk_Section),'') -- Check if is there
    return chunk_without_key_Section, old_chunk_Section -- new chunk, deleted part
end
  
function SwapChunkSection(key,chunk1,chunk2) -- Move Section (key) of chunk1 to chunk2  
    local new_section = GetChunkSection(key, chunk1)
    local new_chunk, _ = RemoveChunkSection(key, chunk2)
    if key == 'AUXVOLENV' or key == 'AUXPANENV' or key == 'AUXMUTEENV' then -- keys that need to be at a specific position
        new_chunk= AddSectionToChunkAfterKey('AUXRECV', new_chunk, new_section) -- Sends Envelope needs to be after Auxrecv 
    else
        new_chunk= AddSectionToChunk(new_chunk, new_section)
    end
    return new_chunk
end


function SwapChunkValue(key, chunk1, chunk2)
    local line1 = chunk1:match(key .. " ([^\n]+)")
    local line2 = chunk2:match(key .. " ([^\n]+)")
    
    if key == "LAYOUTS" then
        -- If no layout in source chunk, get current layout from REAPER
        if not line1 then
            local retval, mcp_layout = reaper.ThemeLayout_GetLayout('mcp', -1)
            local retval2, tcp_layout = reaper.ThemeLayout_GetLayout('tcp', -1)
            if retval and retval2 then
                line1 = mcp_layout .. " " .. tcp_layout
            end
        end
    end
    
    if line1 then
        if line2 then
            -- If both lines exist, replace the line in chunk2
            if key == "LAYOUTS" then
                -- Special handling for LAYOUTS
                local values1 = {}
                local values2 = {}
                for v in line1:gmatch("%S+") do table.insert(values1, v) end
                for v in line2:gmatch("%S+") do table.insert(values2, v) end
                
                -- Update MCP layout (first value) and TCP layout (second value)
                values2[1] = values1[1]
                values2[2] = values1[2]
                
                -- Reconstruct the line
                local new_line = key .. " " .. table.concat(values2, " ")
                chunk2 = chunk2:gsub(key .. " [^\n]+", new_line)
            else
                chunk2 = chunk2:gsub(key .. " [^\n]+", key .. " " .. line1)
            end
        else
            -- If line exists in chunk1 but not in chunk2, add it after TRACK
            if key == "LAYOUTS" then
                -- Special handling for LAYOUTS
                if line1:match("DEFAULT") then
                    -- If the source has DEFAULT layout, we don't need to add the LAYOUTS line
                    -- as REAPER will use the default layout when the line is missing
                    return chunk2
                end
                chunk2 = chunk2:gsub("<TRACK", "<TRACK\n" .. key .. " " .. line1)
            else
                -- For other keys, just add it at the end of the TRACK section
                chunk2 = chunk2:gsub(">", key .. " " .. line1 .. "\n>")
            end
        end
    end
    return chunk2
end

function SwapChunkValueSpecific(chunk1, chunk2, key, indices)
    local line1 = chunk1:match(key .. " ([^\n]+)")
    local line2 = chunk2:match(key .. " ([^\n]+)")
    
    if line1 then
        if line2 then
            -- Split both lines into values
            local values1 = {}
            local values2 = {}
            for v in line1:gmatch("%S+") do table.insert(values1, v) end
            for v in line2:gmatch("%S+") do table.insert(values2, v) end
            
            -- Update only the specified indices
            for _, index in ipairs(indices) do
                values2[index] = values1[index]
            end
            
            -- Reconstruct the line with escaped special characters
            local new_line = key .. " " .. table.concat(values2, " ")
            -- Escape special characters in the replacement string
            new_line = new_line:gsub("[%%]", "%%%%")
            chunk2 = chunk2:gsub(key .. " [^\n]+", new_line)
        else
            -- If line exists in chunk1 but not in chunk2, add it after TRACK
            chunk2 = chunk2:gsub("<TRACK", "<TRACK\n" .. key .. " " .. line1)
        end
    end
    return chunk2
end

function AddSectionToChunk(chunk, section_chunk) -- Track Chunks
    return string.gsub(chunk, '<TRACK', '<TRACK\n'..section_chunk) -- I think I need to literalize this ? 
end

function AddSectionToChunkAfterKey(after_key, new_chunk, new_section) -- If after_key haves a < like <ITEM them input in the string. Just this function haves it
    local tab_chunk = split_by_line(new_chunk)
    local insert_point 
    for i, line in pairs(tab_chunk) do
        if string.starts(line, after_key) then
            insert_point = i
            break
        end  
    end

    local tab_new_section = split_by_line(new_section)
    for i, line in pairs(tab_new_section) do
        local index = insert_point+i
        table.insert(tab_chunk, index, line) 
    end

    return table.concat(tab_chunk,'\n')
end

function GetSendChunk(chunk, send_idx) -- send_idx can be nil to get all send chunks
    if not send_idx then 
        send_idx = ''
    end

    local chunk_table = {}
    local i = 0
    for send_chunk in string.gmatch(chunk,'AUXRECV '..send_idx..'.-\n') do
        while true do
            --local next_line = string.match(chunk,literalize(send_chunk)..'(.-\n)')
            local next_line = match_n(chunk, literalize(send_chunk)..'(.-\n)', i)
            if string.match(next_line,'<AUX') then
                --send_chunk = string.match(chunk, literalize(send_chunk)..literalize(next_line)..'.-\n>\n')
                send_chunk = match_n(chunk, literalize(send_chunk)..literalize(next_line)..'.-\n>\n', i)
            else 
                break
            end
        end
        table.insert(chunk_table, send_chunk)
        i = i + 1
    end
    return chunk_table
end

function SwapChunkValueInSection(section_key, param_key, chunk1, chunk2, indices, new_value)
    print("\n=== SwapChunkValueInSection Debug ===")
    print("Section Key:", section_key)
    print("Parameter Key:", param_key)
    print("Indices to update:", table.concat(indices, ", "))
    if new_value then
        print("New value to set:", new_value)
    end
    
    -- Get the section from both chunks
    local section1 = GetChunkSection(section_key, chunk1)
    local section2 = GetChunkSection(section_key, chunk2)
    
    print("\nSource Section:")
    print(section1)
    print("\nTarget Section:")
    print(section2)
    
    if section1 and section2 then
        -- Find the parameter line in both sections
        local line1 = section1:match(param_key .. " ([^\n]+)")
        local line2 = section2:match(param_key .. " ([^\n]+)")
        
        print("\nSource Parameter Line:", line1)
        print("Target Parameter Line:", line2)
        
        if line1 or new_value then
            if line2 then
                -- Split both lines into values
                local values1 = {}
                local values2 = {}
                if line1 then
                    for v in line1:gmatch("%S+") do table.insert(values1, v) end
                end
                for v in line2:gmatch("%S+") do table.insert(values2, v) end
                
                print("\nSource Values:", table.concat(values1, ", "))
                print("Target Values (before):", table.concat(values2, ", "))
                
                if new_value then
                    -- If new_value is provided, use it instead of source values
                    local new_values = {}
                    for v in new_value:gmatch("%S+") do table.insert(new_values, v) end
                    -- Update only the specified indices with the new values
                    for i, index in ipairs(indices) do
                        values2[index] = new_values[i]
                    end
                else
                    -- Update only the specified indices with source values
                    for _, index in ipairs(indices) do
                        values2[index] = values1[index]
                    end
                end
                
                print("Target Values (after):", table.concat(values2, ", "))
                
                -- Reconstruct the line
                local new_line = param_key .. " " .. table.concat(values2, " ")
                print("\nNew Line:", new_line)
                
                -- Replace the old line in section2
                section2 = section2:gsub(param_key .. " [^\n]+", new_line)
                
                -- Replace the old section in chunk2 with the modified section
                local old_section = GetChunkSection(section_key, chunk2)
                chunk2 = chunk2:gsub(literalize(old_section), section2)
                
                print("\nModified Section:")
                print(section2)
            else
                print("\nParameter line not found in target section, adding it")
                -- If line exists in section1 but not in section2, add it
                section2 = section2:gsub(">", param_key .. " " .. (new_value or line1) .. "\n>")
                
                -- Replace the old section in chunk2 with the modified section
                local old_section = GetChunkSection(section_key, chunk2)
                chunk2 = chunk2:gsub(literalize(old_section), section2)
                
                print("\nModified Section (with added line):")
                print(section2)
            end
        else
            print("\nParameter line not found in source section")
        end
    else
        print("\nOne or both sections not found")
        print("Section1 exists:", section1 ~= nil)
        print("Section2 exists:", section2 ~= nil)
    end
    
    print("\n=== End SwapChunkValueInSection Debug ===\n")
    return chunk2
end