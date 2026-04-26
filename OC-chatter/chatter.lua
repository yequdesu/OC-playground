local component = require("component")
local gpu = component.gpu
local event = require("event")
local term = require("term")
local computer = require("computer")
local unicode = require("unicode")
local filesystem = require("filesystem")

-- ============================================================
-- CONFIG
-- ============================================================

local filepath = (...)
local scriptDir = (type(filepath) == "string") and filesystem.path(filepath) or "."

-- Add script directory to package path for local requires
package.path = package.path .. ";" .. filesystem.concat(scriptDir, "?.lua") .. ";" .. filesystem.concat(scriptDir, "?/init.lua")

local configFile = filesystem.concat(scriptDir, "config.cfg")

local apiKey = nil
local configHandle = io.open(configFile, "r")
if configHandle then
  for line in configHandle:lines() do
    -- Strip comments
    line = line:gsub("%s*#.*$", "")
    if #line == 0 then goto continue end
    
    -- Try quoted value: api_key = "xxx"
    local value = line:match('^api_key%s*=%s*"(.*)"$')
    if value then
      apiKey = value
      break
    end
    
    -- Try single-quoted: api_key = 'xxx'
    value = line:match("^api_key%s*=%s*'([^']*)'$")
    if value then
      apiKey = value
      break
    end
    
    -- Try unquoted: api_key = xxx
    value = line:match("^api_key%s*=%s*(%S+)$")
    if value then
      apiKey = value
      break
    end
    ::continue::
  end
  configHandle:close()
end

if not apiKey or apiKey == "sk-your-deepseek-api-key-here" then
  print("Error: No valid API key found.")
  print("Please edit config.cfg and set your DeepSeek API key.")
  print("Example: api_key = \"sk-xxxxxxxx\"")
  os.exit(1)
end

-- ============================================================
-- IMPORTS
-- ============================================================

local api = require("lib.api")
local deepseek = api.new(apiKey)

-- ============================================================
-- STATE
-- ============================================================

local app = {
  running = true,
  messages = {
    { role = "system", content = "You are a helpful assistant. Be concise and direct." }
  },
  chatLines = {},
  input = "",
  screenWidth = 0,
  screenHeight = 0,
  scrollOffset = 0,
  thinking = false,
  commandMode = false,
  commandInput = ""
}

-- ============================================================
-- COLORS
-- ============================================================

local C = {
  bg = 0x1E1E1E,
  surface = 0x2D2D2D,
  headerBg = 0x3366CC,
  headerText = 0xFFFFFF,
  userLabel = 0x33CC66,
  aiLabel = 0x6699FF,
  text = 0xE1E1E1,
  textSecondary = 0xA0A0A0,
  inputBg = 0x000000,
  inputText = 0xFFFFFF,
  thinking = 0xFFAA00,
  error = 0xFF3333,
  dim = 0x666666,
  border = 0x3D3D3D
}

-- ============================================================
-- TEXT UTILITIES
-- ============================================================

local function wordWrap(text, maxWidth)
  local lines = {}
  local line = ""
  for word in text:gmatch("%S+") do
    if unicode.wlen(line) + unicode.wlen(word) + 1 > maxWidth then
      if #line > 0 then
        table.insert(lines, line)
        line = word
      else
        table.insert(lines, word)
        line = ""
      end
    else
      line = (#line > 0 and line .. " " or "") .. word
    end
  end
  if #line > 0 then table.insert(lines, line) end
  return lines
end

local function wrapLines(text, width)
  local result = {}
  for rawLine in text:gmatch("[^\n]+") do
    local wrapped = wordWrap(rawLine, width)
    for _, wl in ipairs(wrapped) do table.insert(result, wl) end
  end
  if #result == 0 then table.insert(result, "") end
  return result
end

-- ============================================================
-- DRAWING
-- ============================================================

local function fillRect(x, y, w, h, char)
  gpu.fill(x, y, w, h, char or " ")
end

local function drawText(x, y, text)
  gpu.set(x, y, text)
end

local function clearScreen()
  gpu.setBackground(C.bg)
  gpu.setForeground(C.text)
  fillRect(1, 1, app.screenWidth, app.screenHeight, " ")
end

local function drawHeader()
  gpu.setBackground(C.headerBg)
  gpu.setForeground(C.headerText)
  fillRect(1, 1, app.screenWidth, 1, " ")
  drawText(2, 1, "OC-chatter v1.0 :: DeepSeek API")
  
  local status = app.thinking and "[ Thinking... ]" or "[ Ready ]"
  local sx = app.screenWidth - unicode.wlen(status) - 1
  drawText(sx, 1, status)
end

local function drawStatusBar()
  local y = app.screenHeight
  gpu.setBackground(C.surface)
  gpu.setForeground(C.textSecondary)
  fillRect(1, y, app.screenWidth, 1, " ")
  
  local leftHint = "Enter: Send  LEFT: Quit  RIGHT: Clear  Up/Down: Scroll"
  drawText(2, y, leftHint)
  
  local rightInfo = #app.chatLines > 0 and (#app.messages - 1) .. " msgs" or "New"
  local rx = app.screenWidth - unicode.wlen(rightInfo) - 1
  drawText(rx, y, rightInfo)
end

local function appendChat(role, content)
  table.insert(app.messages, { role = role, content = content })
  
  local label = (role == "user") and "You: " or "DeepSeek: "
  local labelColor = (role == "user") and C.userLabel or C.aiLabel
  local prefixWidth = unicode.wlen(label)
  local textWidth = app.screenWidth - 2 - prefixWidth
  
  local wrapped = wrapLines(content, textWidth)
  for i, wline in ipairs(wrapped) do
    table.insert(app.chatLines, {
      text = (i == 1) and wline or wline,
      prefix = (i == 1) and label or nil,
      color = labelColor
    })
  end
  table.insert(app.chatLines, { text = "", prefix = nil })
  
  app.scrollOffset = math.max(0, #app.chatLines - app.screenHeight + 2)
end

local function drawChatArea()
  gpu.setBackground(C.bg)
  local startY = 2
  local chatAreaHeight = app.screenHeight - 2
  
  for y = 1, chatAreaHeight do
    local lineIdx = app.scrollOffset + y
    if lineIdx > #app.chatLines then break end
    local entry = app.chatLines[lineIdx]
    if entry.prefix then
      gpu.setForeground(entry.color)
      drawText(2, startY + y - 1, entry.prefix)
      gpu.setForeground(C.text)
      drawText(2 + unicode.wlen(entry.prefix), startY + y - 1, entry.text)
    else
      gpu.setForeground(C.dim)
      gpu.setBackground(C.bg)
      if #entry.text > 0 then
        drawText(2 + unicode.wlen("DeepSeek: "), startY + y - 1, entry.text)
      end
    end
  end
end

local function drawInputArea()
  local y = app.screenHeight - 1
  gpu.setBackground(C.inputBg)
  gpu.setForeground(C.inputText)
  fillRect(1, y, app.screenWidth, 1, " ")
  
  local prompt = "> "
  local maxDisplay = app.screenWidth - unicode.wlen(prompt) - 2
  local displayInput = app.input
  
  if unicode.wlen(displayInput) > maxDisplay then
    displayInput = unicode.sub(displayInput, -maxDisplay)
  end
  
  drawText(2, y, prompt .. displayInput)
  
  if app.thinking then
    gpu.setForeground(C.thinking)
    drawText(app.screenWidth - 12, y, "[Processing]")
  end
end

local function fullRedraw()
  clearScreen()
  drawHeader()
  drawChatArea()
  drawInputArea()
  drawStatusBar()
end

-- ============================================================
-- EVENTS
-- ============================================================

local function handleKeyDown(code, char)
  if app.thinking then return end
  
  if code == 28 then -- Enter
    if #app.input > 0 then
      local userText = app.input
      app.input = ""
      fullRedraw()
      
      appendChat("user", userText)
      
      app.thinking = true
      fullRedraw()
      
      local response, err = deepseek:chat(app.messages)
      
      if response then
        appendChat("assistant", response)
      else
        table.insert(app.messages, { role = "assistant", content = "[Error: " .. tostring(err) .. "]" })
        table.insert(app.chatLines, { text = "[Error: " .. tostring(err) .. "]", prefix = "DeepSeek: ", color = C.error })
      end
      
      app.thinking = false
      fullRedraw()
    end
  elseif code == 14 then -- Backspace
    if #app.input > 0 then
      app.input = unicode.sub(app.input, 1, -2)
    end
  elseif code == 203 then -- LEFT arrow: quit
    app.running = false
  elseif code == 205 then -- RIGHT arrow: clear
    app.messages = { { role = "system", content = "You are a helpful assistant. Be concise and direct." } }
    app.chatLines = {}
    app.scrollOffset = 0
    fullRedraw()
  elseif code == 200 then -- Up arrow: scroll up
    app.scrollOffset = math.max(0, app.scrollOffset - 3)
    fullRedraw()
  elseif code == 208 then -- Down arrow: scroll down
    local maxScroll = #app.chatLines - app.screenHeight + 2
    if maxScroll < 0 then maxScroll = 0 end
    app.scrollOffset = math.min(maxScroll, app.scrollOffset + 3)
    fullRedraw()
  else
    -- Character input — handle both string and number
    local inputChar = ""
    if type(char) == "string" and #char > 0 then
      inputChar = char
    elseif type(char) == "number" and char >= 32 then
      inputChar = string.char(char)
    end
    if #inputChar > 0 then
      app.input = app.input .. inputChar
    end
  end
end

local function handleScroll(dir)
  local maxScroll = #app.chatLines - app.screenHeight + 2
  if maxScroll < 0 then maxScroll = 0 end
  if dir > 0 then
    app.scrollOffset = math.max(0, app.scrollOffset - 1)
  else
    app.scrollOffset = math.min(maxScroll, app.scrollOffset + 1)
  end
end

-- ============================================================
-- MAIN
-- ============================================================

local function init()
  gpu.setResolution(160, 50)
  app.screenWidth, app.screenHeight = gpu.getResolution()
  
  clearScreen()
  fullRedraw()
  
  while app.running do
    local e1, e2, e3, e4, e5 = event.pull(0.1)
    if e1 then
      if e1 == "key_down" then
        handleKeyDown(e4, e3)
      elseif e1 == "scroll" then
        handleScroll(e5)
      end
      fullRedraw()
    end
  end
  
  term.clear()
  os.exit(0)
end

init()