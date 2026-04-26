local json = {}

local function escapeString(str)
  return str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

function json.encode(value)
  local t = type(value)
  if t == "string" then
    return '"' .. escapeString(value) .. '"'
  elseif t == "number" then
    if value % 1 == 0 then
      return string.format("%d", value)
    else
      return string.format("%.14g", value)
    end
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "nil" then
    return "null"
  elseif t == "table" then
    local isArray = true
    local maxIndex = 0
    for k in pairs(value) do
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        isArray = false
        break
      end
      if k > maxIndex then maxIndex = k end
    end
    if isArray and maxIndex > 0 then
      local parts = {}
      for i = 1, maxIndex do
        parts[i] = json.encode(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(value) do
        if type(k) == "string" then
          parts[#parts + 1] = '"' .. escapeString(k) .. '":' .. json.encode(v)
        else
          parts[#parts + 1] = '"' .. tostring(k) .. '":' .. json.encode(v)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

-- Store parse functions in json table to avoid LuaJ upvalue issues
json.null = {}

function json.decode(str)
  if type(str) ~= "string" then return nil, "expected string" end
  
  local pos = 1
  
  local function skipWs()
    while pos <= #str do
      local ch = str:sub(pos, pos)
      if ch ~= " " and ch ~= "\n" and ch ~= "\r" and ch ~= "\t" then break end
      pos = pos + 1
    end
  end
  
  local function parseStringVal()
    pos = pos + 1
    local result = {}
    while pos <= #str do
      local ch = str:sub(pos, pos)
      if ch == '"' then
        pos = pos + 1
        return table.concat(result)
      elseif ch == '\\' then
        pos = pos + 1
        ch = str:sub(pos, pos)
        if ch == 'n' then result[#result + 1] = '\n'
        elseif ch == 'r' then result[#result + 1] = '\r'
        elseif ch == 't' then result[#result + 1] = '\t'
        elseif ch == 'u' then
          result[#result + 1] = string.char(tonumber(str:sub(pos + 1, pos + 4), 16))
          pos = pos + 4
        else result[#result + 1] = ch end
      else
        result[#result + 1] = ch
      end
      pos = pos + 1
    end
    return nil
  end
  
  local function parseNumVal()
    local startPos = pos
    if str:sub(pos, pos) == '-' then pos = pos + 1 end
    while pos <= #str and str:sub(pos, pos) >= '0' and str:sub(pos, pos) <= '9' do pos = pos + 1 end
    if str:sub(pos, pos) == '.' then
      pos = pos + 1
      while pos <= #str and str:sub(pos, pos) >= '0' and str:sub(pos, pos) <= '9' do pos = pos + 1 end
    end
    if str:sub(pos, pos) == 'e' or str:sub(pos, pos) == 'E' then
      pos = pos + 1
      if str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-' then pos = pos + 1 end
      while pos <= #str and str:sub(pos, pos) >= '0' and str:sub(pos, pos) <= '9' do pos = pos + 1 end
    end
    return tonumber(str:sub(startPos, pos - 1))
  end
  
  -- main parse: one recursive function closure
  local function parse()
    skipWs()
    if pos > #str then return nil end
    local ch = str:sub(pos, pos)
    
    if ch == '"' then
      return parseStringVal()
    elseif ch == '{' then
      pos = pos + 1
      local obj = {}
      skipWs()
      if str:sub(pos, pos) == '}' then pos = pos + 1 return obj end
      while true do
        skipWs()
        local key = parseStringVal()
        if not key then return nil end
        skipWs()
        if str:sub(pos, pos) ~= ':' then return nil end
        pos = pos + 1
        local value = parse()
        obj[key] = (value == json.null) and nil or value
        skipWs()
        local sep = str:sub(pos, pos)
        if sep == '}' then pos = pos + 1 return obj
        elseif sep == ',' then pos = pos + 1
        else return nil end
      end
    elseif ch == '[' then
      pos = pos + 1
      local arr = {}
      skipWs()
      if str:sub(pos, pos) == ']' then pos = pos + 1 return arr end
      local i = 1
      while true do
        local value = parse()
        arr[i] = (value == json.null) and nil or value
        i = i + 1
        skipWs()
        local sep = str:sub(pos, pos)
        if sep == ']' then pos = pos + 1 return arr
        elseif sep == ',' then pos = pos + 1
        else return nil end
      end
    elseif ch == 't' and str:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif ch == 'f' and str:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif ch == 'n' and str:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return json.null
    elseif ch == '-' or (ch >= '0' and ch <= '9') then
      return parseNumVal()
    end
    return nil
  end
  
  local value = parse()
  skipWs()
  if pos <= #str then return nil, "trailing garbage at position " .. pos end
  return value
end

return json