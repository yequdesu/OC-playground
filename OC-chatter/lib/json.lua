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

json.null = {}

function json.decode(str)
  if type(str) ~= "string" then return nil, "expected string" end

  -- MineOS / rxi-style: use a shared pos variable and local parse functions
  -- Forward declare the main recursive parser
  local parse, skipWs, parseStr, parseNum

  skipWs = function(str, pos)
    while pos <= #str do
      local ch = str:sub(pos, pos)
      if ch ~= " " and ch ~= "\n" and ch ~= "\r" and ch ~= "\t" then break end
      pos = pos + 1
    end
    return pos
  end

  parseStr = function(str, pos)
    pos = pos + 1
    local result = {}
    while pos <= #str do
      local ch = str:sub(pos, pos)
      if ch == '"' then
        return table.concat(result), pos + 1
      elseif ch == '\\' then
        pos = pos + 1
        ch = str:sub(pos, pos)
        if ch == 'n' then result[#result + 1] = '\n'
        elseif ch == 'r' then result[#result + 1] = '\r'
        elseif ch == 't' then result[#result + 1] = '\t'
        elseif ch == 'u' then
          local hex = str:sub(pos + 1, pos + 4)
          result[#result + 1] = string.char(tonumber(hex, 16))
          pos = pos + 4
        else result[#result + 1] = ch end
      else
        result[#result + 1] = ch
      end
      pos = pos + 1
    end
    return nil, pos
  end

  parseNum = function(str, pos)
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
    return tonumber(str:sub(startPos, pos - 1)), pos
  end

  parse = function(str, pos)
    pos = skipWs(str, pos)
    if pos > #str then return nil, pos end
    local ch = str:sub(pos, pos)

    if ch == '"' then
      return parseStr(str, pos)
    elseif ch == '{' then
      pos = pos + 1
      local obj = {}
      pos = skipWs(str, pos)
      if str:sub(pos, pos) == '}' then return obj, pos + 1 end
      while true do
        pos = skipWs(str, pos)
        local key
        key, pos = parseStr(str, pos)
        if not key then return nil, pos end
        pos = skipWs(str, pos)
        if str:sub(pos, pos) ~= ':' then return nil, pos end
        pos = pos + 1
        local value
        value, pos = parse(str, pos)
        obj[key] = (value == json.null) and nil or value
        pos = skipWs(str, pos)
        local sep = str:sub(pos, pos)
        if sep == '}' then return obj, pos + 1
        elseif sep == ',' then pos = pos + 1
        else return nil, pos end
      end
    elseif ch == '[' then
      pos = pos + 1
      local arr = {}
      pos = skipWs(str, pos)
      if str:sub(pos, pos) == ']' then return arr, pos + 1 end
      local i = 1
      while true do
        local value
        value, pos = parse(str, pos)
        arr[i] = (value == json.null) and nil or value
        i = i + 1
        pos = skipWs(str, pos)
        local sep = str:sub(pos, pos)
        if sep == ']' then return arr, pos + 1
        elseif sep == ',' then pos = pos + 1
        else return nil, pos end
      end
    elseif ch == 't' and str:sub(pos, pos + 3) == "true" then
      return true, pos + 4
    elseif ch == 'f' and str:sub(pos, pos + 4) == "false" then
      return false, pos + 5
    elseif ch == 'n' and str:sub(pos, pos + 3) == "null" then
      return json.null, pos + 4
    elseif ch == '-' or (ch >= '0' and ch <= '9') then
      return parseNum(str, pos)
    end
    return nil, pos
  end

  local value, pos = parse(str, 1)
  pos = skipWs(str, pos)
  if pos <= #str then return nil, "trailing garbage" end
  return value
end

return json