local component = require("component")
local gpu = component.gpu
local event = require("event")
local term = require("term")
local unicode = require("unicode")
local filesystem = require("filesystem")
local computer = require("computer")
local os = require("os")

local args = {...}

-- ============================================================
-- UTILITIES
-- ============================================================

local function r8(file)
  local byte = file:read(1)
  if byte == nil then return 0
  else return string.byte(byte) & 255 end
end

local function r16(file)
  local x = r8(file)
  return x | (r8(file) << 8)
end

local function gpuGetBackground()
  local a, al = gpu.getBackground()
  if al then return gpu.getPaletteColor(a)
  else return a end
end

local function gpuGetForeground()
  local a, al = gpu.getForeground()
  if al then return gpu.getPaletteColor(a)
  else return a end
end

-- ============================================================
-- CTIF IMAGE LOADING
-- ============================================================

local function isValidCTIF(filename)
  local file = io.open(filename, "rb")
  if not file then return false end
  local hdr = {67, 84, 73, 70}
  for i = 1, 4 do
    if r8(file) ~= hdr[i] then file:close() return false end
  end
  local hdrVersion = r8(file)
  if hdrVersion > 1 then file:close() return false end
  local platformVariant = r8(file)
  local platformId = r16(file)
  if platformId ~= 1 or platformVariant ~= 0 then file:close() return false end
  file:close()
  return true
end

local function scanDirectory(dir)
  local images = {}
  local files = filesystem.list(dir)
  if files then
    for file in files do
      if string.sub(file, -5) == ".ctif" then
        local fullPath = filesystem.concat(dir, file)
        if isValidCTIF(fullPath) then table.insert(images, fullPath) end
      end
    end
  end
  return images
end

local function loadImage(filename)
  local data = {}
  local file = io.open(filename, "rb")
  if not file then return nil end

  local hdr = {67, 84, 73, 70}
  for i = 1, 4 do
    if r8(file) ~= hdr[i] then file:close() return nil end
  end

  local hdrVersion = r8(file)
  local platformVariant = r8(file)
  local platformId = r16(file)

  if hdrVersion > 1 then file:close() return nil end
  if platformId ~= 1 or platformVariant ~= 0 then file:close() return nil end

  data[1] = {}
  data[2] = {}
  data[3] = {}
  data[2][1] = r8(file)
  data[2][1] = (data[2][1] | (r8(file) << 8))
  data[2][2] = r8(file)
  data[2][2] = (data[2][2] | (r8(file) << 8))

  local pw = r8(file)
  local ph = r8(file)
  if not (pw == 2 and ph == 4) then file:close() return nil end

  data[2][3] = r8(file)
  if (data[2][3] ~= 4 and data[2][3] ~= 8) or data[2][3] > gpu.getDepth() then
    file:close() return nil
  end

  local ccEntrySize = r8(file)
  local customColors = r16(file)
  if customColors > 0 and ccEntrySize ~= 3 then file:close() return nil end
  if customColors > 16 then file:close() return nil end

  for p = 0, customColors - 1 do
    local w = r16(file)
    data[3][p] = w | (r8(file) << 16)
  end

  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]

  for y = 0, HEIGHT - 1 do
    for x = 0, WIDTH - 1 do
      local j = (y * WIDTH) + x + 1
      local w = r16(file)
      if data[2][3] > 4 then
        data[1][j] = w | (r8(file) << 16)
      else
        data[1][j] = w
      end
    end
  end

  file:close()
  return data
end

-- ============================================================
-- IMAGE DRAWING
-- ============================================================

local function generatePalette(data)
  local pal = {}
  for i = 0, 255 do
    if i < 16 then
      if data and data[3] and data[3][i] then
        pal[i] = data[3][i]
        gpu.setPaletteColor(i, data[3][i])
      else
        pal[i] = (i * 15) << 16 | (i * 15) << 8 | (i * 15)
      end
    else
      local j = i - 16
      local b = math.floor((j % 5) * 255 / 4.0)
      local g = math.floor((math.floor(j / 5.0) % 8) * 255 / 7.0)
      local r = math.floor((math.floor(j / 40.0) % 6) * 255 / 5.0)
      pal[i] = r << 16 | g << 8 | b
    end
  end
  return pal
end

local function drawImage(data, offx, offy)
  offx = offx or 0
  offy = offy or 0
  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]

  local pal = generatePalette(data)
  local gBG = gpuGetBackground()
  local gFG = gpuGetForeground()

  local q = {}
  for i = 0, 255 do
    local dat = (i & 0x01) << 7
    dat = dat | ((i & 0x02) >> 1) << 6
    dat = dat | ((i & 0x04) >> 2) << 5
    dat = dat | ((i & 0x08) >> 3) << 2
    dat = dat | ((i & 0x10) >> 4) << 4
    dat = dat | ((i & 0x20) >> 5) << 1
    dat = dat | ((i & 0x40) >> 6) << 3
    dat = dat | ((i & 0x80) >> 7)
    q[i + 1] = unicode.char(0x2800 | dat)
  end

  for y = 0, HEIGHT - 1 do
    local str = ""
    for x = 0, WIDTH - 1 do
      local ind = (y * WIDTH) + x + 1
      local bg, fg, cw
      if data[2][3] > 4 then
        bg = pal[data[1][ind] & 0xFF]
        fg = pal[(data[1][ind] >> 8) & 0xFF]
        cw = ((data[1][ind] >> 16) & 0xFF) + 1
      else
        fg = pal[data[1][ind] & 0x0F]
        bg = pal[(data[1][ind] >> 4) & 0x0F]
        cw = ((data[1][ind] >> 8) & 0xFF) + 1
      end
      local noBG = (cw == 256)
      local noFG = (cw == 1)

      if (noFG or (gBG == fg)) and (noBG or (gFG == bg)) then
        str = str .. q[257 - cw]
      elseif (noBG or (gBG == bg)) and (noFG or (gFG == fg)) then
        str = str .. q[cw]
      else
        if #str > 0 then
          gpu.set(x + 1 + offx - unicode.wlen(str), y + 1 + offy, str)
          str = ""
        end
        if (gBG == fg and gFG ~= bg) or (gFG == bg and gBG ~= fg) then
          cw = 257 - cw
          local t = bg; bg = fg; fg = t
        end
        if gBG ~= bg then gpu.setBackground(bg); gBG = bg end
        if gFG ~= fg then gpu.setForeground(fg); gFG = fg end
        str = q[cw]
      end
    end
    if #str > 0 then gpu.set(WIDTH + 1 - unicode.wlen(str) + offx, y + 1 + offy, str) end
  end
end

-- ============================================================
-- APP STATE
-- ============================================================

local COLORS = {
  primary = 0x3366CC,
  background = 0x1E1E1E,
  surface = 0x2D2D2D,
  text = 0xFFFFFF,
  textSecondary = 0xA0A0A0
}

local app = {
  mode = "browser",  -- "browser", "viewer", "cli"
  images = {},
  selectedIndex = 1,
  viewIndex = 1,
  scrollOffset = 0,
  maxVisibleItems = 0,
  screenWidth = 0,
  screenHeight = 0,
  currentDir = ".",
  
  -- Debug info
  lastKeyCode = 0,
  lastKeyChar = "",
  lastEventType = "",
  lastTouchX = 0,
  lastTouchY = 0,
  lastTouchButton = 0,
  
  -- CLI state
  cliActive = false,
  cliInput = "",
  cliState = "idle",  -- "idle", "command", "url", "filename"
  targetURL = "",
  
  -- Cursor blink
  cursorBlink = true,
  lastCursorTime = 0,
  lastStatusBarTime = 0,
}

-- ============================================================
-- SCREEN UTILITIES
-- ============================================================

local function resetScreen()
  local x, y = gpu.maxResolution()
  gpu.setResolution(x, y)
end

local function clearScreen(color)
  color = color or 0x000000
  gpu.setBackground(color, false)
  gpu.setForeground(0xFFFFFF, false)
  term.clear()
end

local function drawText(x, y, text)
  gpu.set(x, y, text)
end

local function fillRect(x, y, w, h, char)
  gpu.fill(x, y, w, h, char or " ")
end

local function updateScreenSize()
  app.screenWidth, app.screenHeight = gpu.getResolution()
  app.maxVisibleItems = app.screenHeight - 5
end

local function getImageName(path)
  return filesystem.name(path)
end

-- ============================================================
-- UI: HEADER & STATUS BAR
-- ============================================================

local function drawHeader()
  gpu.setBackground(COLORS.surface)
  gpu.setForeground(COLORS.text)
  fillRect(1, 1, app.screenWidth, 1, " ")
  drawText(2, 1, "CTIF Image Viewer")
  drawText(app.screenWidth - 15, 1, #app.images .. " images")
end

local function drawStatusBar()
  local y = app.screenHeight
  gpu.setBackground(COLORS.surface)
  gpu.setForeground(COLORS.textSecondary)
  fillRect(1, y, app.screenWidth, 1, " ")
  
  -- Left side: hints
  if app.mode == "browser" then
    drawText(2, y, "UP/DOWN: Navigate  ENTER: View  C: CLI")
  elseif app.mode == "viewer" then
    drawText(2, y, "LEFT/RIGHT: Prev/Next  ESC: Back")
  elseif app.mode == "cli" then
    drawText(2, y, "CLI Mode - Enter command  Ctrl+C: Exit CLI")
  end
  
  -- Right side: debug info
  local debug = ""
  if app.lastEventType == "touch" then
    debug = string.format("Touch:%d,%d Btn:%d", app.lastTouchX, app.lastTouchY, app.lastTouchButton)
  else
    debug = string.format("Key:%d Char:'%s'", app.lastKeyCode, app.lastKeyChar)
  end
  local dx = app.screenWidth - unicode.wlen(debug) - 1
  drawText(dx, y, debug)
end

-- ============================================================
-- UI: IMAGE LIST
-- ============================================================

local function drawImageList()
  local startY = 3
  local visibleCount = math.min(#app.images - app.scrollOffset, app.maxVisibleItems)

  gpu.setBackground(COLORS.background)
  gpu.setForeground(COLORS.text)
  fillRect(1, startY, app.screenWidth, app.screenHeight - 3, " ")

  for i = 1, visibleCount do
    local idx = app.scrollOffset + i
    if idx > #app.images then break end

    local y = startY + i - 1
    local isSelected = (idx == app.selectedIndex)
    local name = getImageName(app.images[idx])

    if isSelected then
      gpu.setBackground(COLORS.primary)
      gpu.setForeground(COLORS.text)
    else
      gpu.setBackground(COLORS.background)
      if i % 2 == 0 then gpu.setBackground(0x252525) end
      gpu.setForeground(COLORS.text)
    end

    fillRect(1, y, app.screenWidth, 1, " ")
    local prefix = isSelected and " > " or "   "
    gpu.set(2, y, prefix)
    gpu.set(5, y, name)
  end

  if #app.images == 0 then
    gpu.setForeground(COLORS.textSecondary)
    drawText(math.floor(app.screenWidth / 2 - 10), startY + 2, "No CTIF images found")
  end
end

local function scrollToSelection()
  if app.selectedIndex <= app.scrollOffset then
    app.scrollOffset = app.selectedIndex - 1
  elseif app.selectedIndex > app.scrollOffset + app.maxVisibleItems then
    app.scrollOffset = app.selectedIndex - app.maxVisibleItems
  end
  app.scrollOffset = math.max(0, app.scrollOffset)
end

-- ============================================================
-- UI: IMAGE VIEWER
-- ============================================================

local function drawImageViewer()
  local data = loadImage(app.images[app.viewIndex])
  if not data then return end

  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]
  local startX = math.floor((app.screenWidth - WIDTH) / 2)
  local startY = math.floor((app.screenHeight - HEIGHT) / 2)

  gpu.setBackground(0x000000)
  term.clear()
  drawImage(data, startX, startY)

  gpu.setBackground(COLORS.surface)
  gpu.setForeground(COLORS.textSecondary)
  fillRect(1, app.screenHeight, app.screenWidth, 1, " ")
  drawText(2, app.screenHeight, getImageName(app.images[app.viewIndex]))
  drawText(app.screenWidth - 20, app.screenHeight, app.viewIndex .. "/" .. #app.images)
end

-- ============================================================
-- UI: CLI (NANO-STYLE AT BOTTOM)
-- ============================================================

local function drawCLI()
  -- CLI input area is at the bottom, above status bar
  local cliY = app.screenHeight - 2
  
  -- Clear CLI area
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  fillRect(1, cliY, app.screenWidth, 2, " ")
  
  -- Input line
  local prompt = ""
  if app.cliState == "command" then
    prompt = "Command> " .. app.cliInput
  elseif app.cliState == "url" then
    prompt = "URL> " .. app.cliInput
  elseif app.cliState == "filename" then
    prompt = "File> " .. app.cliInput
  else
    prompt = "> " .. app.cliInput
  end
  
  -- Cursor blink
  local cursorChar = "_"
  if app.cursorBlink then
    cursorChar = "█"
  end
  
  drawText(2, cliY, prompt .. cursorChar)
  
  -- Hint line
  local hint = "Ctrl+C:Exit CLI"
  if app.cliState == "command" then
    hint = "Commands: help, dl, q | Ctrl+C:Exit"
  elseif app.cliState == "url" then
    hint = "Enter URL and press ENTER"
  elseif app.cliState == "filename" then
    hint = "Enter filename (empty = default)"
  end
  drawText(2, cliY + 1, hint)
end

local function showCLI()
  app.mode = "cli"
  app.cliActive = true
  app.cliInput = ""
  app.cliState = "command"
  app.lastCursorTime = computer.uptime()
  drawCLI()
  drawStatusBar()
end

local function hideCLI()
  app.mode = "browser"
  app.cliActive = false
  app.cliInput = ""
  app.cliState = "idle"
end

-- ============================================================
-- DOWNLOAD (PLACEHOLDER)
-- ============================================================

local function deriveFilenameFromURL(url)
  local last = url:match(".*/([^/?#]+)$") or "download.ctif"
  local name, ext = last:match("([^%.]+)%.([^%.]+)$")
  local ts = tostring(os.time())
  if ext then
    return (name or "download") .. "_" .. ts .. "." .. ext
  else
    return last .. "_" .. ts
  end
end

local function drawProgressModal(percent, message)
  local w, h = 50, 8
  local bx = math.floor((app.screenWidth - w) / 2)
  local by = math.floor((app.screenHeight - h) / 2)
  
  gpu.setBackground(0x000000)
  fillRect(bx, by, w, h, " ")
  
  -- Border
  gpu.setBackground(0x3366CC)
  fillRect(bx, by, w, 1, " ")
  fillRect(bx, by + h - 1, w, 1, " ")
  for y = by + 1, by + h - 2 do
    gpu.set(bx, y, "│")
    gpu.set(bx + w - 1, y, "│")
  end
  
  -- Title
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  drawText(bx + 2, by + 1, "Downloading...")
  
  -- Progress bar
  local barW = w - 6
  local filled = math.floor((percent / 100) * barW)
  gpu.setForeground(0x33CC66)
  drawText(bx + 3, by + 3, string.rep("█", filled))
  gpu.setForeground(0x666666)
  drawText(bx + 3 + filled, by + 3, string.rep("─", barW - filled))
  
  -- Percent
  gpu.setForeground(0xFFFFFF)
  drawText(bx + 2, by + 5, message .. " " .. percent .. "%")
end

local function beginDownload(url)
  app.cliState = "downloading"
  
  -- Simulate download progress
  for p = 0, 100, 10 do
    drawProgressModal(p, "Downloading...")
  end
  
  drawProgressModal(100, "Complete!")
  
  -- Ask for filename
  local defName = deriveFilenameFromURL(url)
  app.cliState = "filename"
  app.cliInput = defName
  app.targetURL = url
  drawCLI()
end

-- ============================================================
-- MAIN VIEWS
-- ============================================================

local function showBrowser()
  app.mode = "browser"
  updateScreenSize()
  clearScreen(COLORS.background)
  drawHeader()
  drawImageList()
  drawStatusBar()
end

local function showViewer()
  app.mode = "viewer"
  drawImageViewer()
  drawStatusBar()
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

local function handleKeyDown(code, char)
  -- Update debug info immediately
  app.lastKeyCode = code
  app.lastKeyChar = (char and char ~= "" and type(char) == "string") and char or ""
  app.lastEventType = "key_down"
  
  -- CLI mode input handling
  if app.cliActive then
    -- Ctrl (code 29) exits CLI
    if code == 29 then
      hideCLI()
      showBrowser()
      return
    end
    
    if code == 28 then -- ENTER
      local input = app.cliInput
      app.cliInput = ""
      
      if app.cliState == "command" then
        local cmd = input:lower()
        if cmd == "help" then
          -- Show help in CLI area
          gpu.setBackground(0x000000)
          gpu.setForeground(0xFFFFFF)
          fillRect(1, app.screenHeight - 4, app.screenWidth, 3, " ")
          drawText(2, app.screenHeight - 3, "help - show commands")
          drawText(2, app.screenHeight - 2, "dl  - download CTIF")
          drawText(2, app.screenHeight - 1, "q   - quit program")
          app.cliInput = ""
          app.cliState = "command"
          drawCLI()
        elseif cmd == "dl" then
          app.cliState = "url"
          app.cliInput = ""
          drawCLI()
        elseif cmd == "q" then
          os.exit(0)
        else
          app.cliInput = ""
          drawCLI()
        end
      elseif app.cliState == "url" then
        if input and input ~= "" then
          app.targetURL = input
          beginDownload(input)
        else
          app.cliState = "command"
          app.cliInput = ""
          drawCLI()
        end
      elseif app.cliState == "filename" then
        local fname = (input == "" or input == nil) and deriveFilenameFromURL(app.targetURL) or input
        local dest = (app.currentDir or ".") .. "/" .. fname
        local f = io.open(dest, "wb")
        if f then f:close() end
        -- Refresh directory
        app.images = scanDirectory(app.currentDir or ".")
        hideCLI()
        showBrowser()
      end
      drawStatusBar()
      return
    elseif code == 14 then -- BACKSPACE
      if #app.cliInput > 0 then
        app.cliInput = string.sub(app.cliInput, 1, -2)
      end
    else
      -- Use char directly from event, filter control characters
      if char and type(char) == "string" and #char > 0 then
        local byte = string.byte(char)
        -- Allow printable characters (32-126) and extended ASCII
        if byte and byte >= 32 then
          app.cliInput = app.cliInput .. char
        end
      end
    end
    
    drawCLI()
    drawStatusBar()
    return
  end
  
  -- Browser mode
  if app.mode == "browser" then
    if code == 200 then -- UP
      app.selectedIndex = app.selectedIndex > 1 and app.selectedIndex - 1 or #app.images
      scrollToSelection()
      drawImageList()
      drawStatusBar()
    elseif code == 208 then -- DOWN
      app.selectedIndex = app.selectedIndex < #app.images and app.selectedIndex + 1 or 1
      scrollToSelection()
      drawImageList()
      drawStatusBar()
    elseif code == 28 then -- ENTER
      app.viewIndex = app.selectedIndex
      showViewer()
    elseif code == 46 or (char and (char == "c" or char == "C")) then -- C key (46) or char 'c'/'C'
      showCLI()
    end
  elseif app.mode == "viewer" then
    if code == 200 then -- LEFT
      app.viewIndex = app.viewIndex > 1 and app.viewIndex - 1 or #app.images
      showViewer()
    elseif code == 208 then -- RIGHT
      app.viewIndex = app.viewIndex < #app.images and app.viewIndex + 1 or 1
      showViewer()
    elseif code == 203 or code == 1 then -- LEFT or ESC
      showBrowser()
    end
  end
end

-- Handle key_up events for debug display
local function handleKeyUp(code, char)
  app.lastKeyCode = code
  app.lastKeyChar = (char and char ~= "" and type(char) == "string") and char or ""
  app.lastEventType = "key_up"
  drawStatusBar()
end

local function handleTouch(x, y, button)
  app.lastTouchX = x
  app.lastTouchY = y
  app.lastTouchButton = button
  app.lastEventType = "touch"
  
  if app.mode == "browser" then
    local startY = 3
    if y >= startY and y < startY + app.maxVisibleItems then
      local idx = app.scrollOffset + (y - startY + 1)
      if idx >= 1 and idx <= #app.images then
        app.selectedIndex = idx
        drawImageList()
        drawStatusBar()
      end
    end
  end
end

local function handleScroll(dir)
  if app.mode == "browser" then
    if dir > 0 then
      app.selectedIndex = app.selectedIndex > 1 and app.selectedIndex - 1 or #app.images
    else
      app.selectedIndex = app.selectedIndex < #app.images and app.selectedIndex + 1 or 1
    end
    scrollToSelection()
    drawImageList()
    drawStatusBar()
  end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================

local function init(dir)
  if not filesystem.exists(dir) or not filesystem.isDirectory(dir) then
    print("Error: Invalid directory: " .. dir)
    os.exit(1)
  end

  app.images = scanDirectory(dir)
  app.currentDir = dir
  if #app.images == 0 then
    print("No valid CTIF images found.")
    os.exit(1)
  end

  showBrowser()

  while true do
    -- Cursor blink timer
    local now = computer.uptime()
    local needsRedraw = false
    
    if app.cliActive and now - app.lastCursorTime > 0.5 then
      app.cursorBlink = not app.cursorBlink
      app.lastCursorTime = now
      if app.cliActive then drawCLI() end
    end
    
    -- Periodic status bar refresh to keep debug info visible
    if now - app.lastStatusBarTime > 0.3 then
      app.lastStatusBarTime = now
      drawStatusBar()
    end
    
    -- Pull events
    local e1, e2, e3, e4, e5, e6 = event.pull(0.1)
    if e1 then
      -- Reset status bar timer on any event and update debug info
      app.lastStatusBarTime = now
      
      -- Always capture and display ALL events for debug
      if e1 == "key_down" then
        app.lastEventType = "key_down"
        app.lastKeyCode = e4
        app.lastKeyChar = (e3 and type(e3) == "string" and #e3 > 0) and e3 or ""
        handleKeyDown(e4, e3)
      elseif e1 == "key_up" then
        app.lastEventType = "key_up"
        app.lastKeyCode = e4
        app.lastKeyChar = (e3 and type(e3) == "string" and #e3 > 0) and e3 or ""
        handleKeyUp(e4, e3)
      elseif e1 == "touch" then
        app.lastEventType = "touch"
        app.lastTouchX = e3
        app.lastTouchY = e4
        app.lastTouchButton = e5 or 0
        handleTouch(e3, e4, e5 or 0)
      elseif e1 == "drag" then
        app.lastEventType = "drag"
        app.lastTouchX = e3
        app.lastTouchY = e4
        app.lastTouchButton = e5 or 0
        handleTouch(e3, e4, e5 or 0)
      elseif e1 == "scroll" then
        app.lastEventType = "scroll"
        handleScroll(e4)
      end
      
      -- Always redraw status bar after any event
      drawStatusBar()
    end
  end
end

local dir = args[1] or "/"
init(dir)