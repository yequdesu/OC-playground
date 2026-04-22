local component = require("component")
local gpu = component.gpu
local event = require("event")
local term = require("term")
local unicode = require("unicode")
local filesystem = require("filesystem")
local computer = require("computer")

local args = {...}

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

local function drawImage(data, offx, offy, saveResolution)
  offx = offx or 0
  offy = offy or 0
  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]

  if saveResolution then gpu.setResolution(WIDTH, HEIGHT) end

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

local COLORS = {
  primary = 0x3366CC,
  background = 0x1E1E1E,
  surface = 0x2D2D2D,
  text = 0xFFFFFF,
  textSecondary = 0xA0A0A0
}

local app = {
  mode = "browser",
  images = {},
  selectedIndex = 1,
  viewIndex = 1,
  scrollOffset = 0,
  maxVisibleItems = 0,
  screenWidth = 0,
  screenHeight = 0
}

local function updateScreenSize()
  app.screenWidth, app.screenHeight = gpu.getResolution()
  app.maxVisibleItems = app.screenHeight - 6
end

local function getImageName(path)
  return filesystem.name(path)
end

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
  drawText(2, y, "UP/DOWN: Navigate  ENTER: View  ESC: Exit")
end

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

local function drawImageViewer()
  local data = loadImage(app.images[app.viewIndex])
  if not data then return end

  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]
  local startX = math.floor((app.screenWidth - WIDTH) / 2)
  local startY = math.floor((app.screenHeight - HEIGHT) / 2)

  gpu.setBackground(0x000000)
  term.clear()
  drawImage(data, startX, startY, false)

  gpu.setBackground(COLORS.surface)
  gpu.setForeground(COLORS.textSecondary)
  fillRect(1, app.screenHeight, app.screenWidth, 1, " ")
  drawText(2, app.screenHeight, getImageName(app.images[app.viewIndex]))
  drawText(app.screenWidth - 20, app.screenHeight, app.viewIndex .. "/" .. #app.images)
  drawText(app.screenWidth - 8, app.screenHeight, "ESC: Back")
end

local function showBrowser()
  app.mode = "browser"
  resetScreen()
  updateScreenSize()
  clearScreen(COLORS.background)
  drawHeader()
  drawImageList()
  drawStatusBar()
end

local function showViewer()
  app.mode = "viewer"
  drawImageViewer()
end

local function scrollToSelection()
  if app.selectedIndex <= app.scrollOffset then
    app.scrollOffset = app.selectedIndex - 1
  elseif app.selectedIndex > app.scrollOffset + app.maxVisibleItems then
    app.scrollOffset = app.selectedIndex - app.maxVisibleItems
  end
  app.scrollOffset = math.max(0, app.scrollOffset)
end

local function handleKeyDown(code)
  if app.mode == "browser" then
    if code == 200 then
      app.selectedIndex = app.selectedIndex > 1 and app.selectedIndex - 1 or #app.images
      scrollToSelection()
      drawImageList()
      drawStatusBar()
    elseif code == 208 then
      app.selectedIndex = app.selectedIndex < #app.images and app.selectedIndex + 1 or 1
      scrollToSelection()
      drawImageList()
      drawStatusBar()
    elseif code == 28 then
      app.viewIndex = app.selectedIndex
      showViewer()
    elseif code == 1 then
      computer.pushSignal("exit")
    end
  elseif app.mode == "viewer" then
    if code == 200 then
      app.viewIndex = app.viewIndex > 1 and app.viewIndex - 1 or #app.images
      showViewer()
    elseif code == 208 then
      app.viewIndex = app.viewIndex < #app.images and app.viewIndex + 1 or 1
      showViewer()
    elseif code == 203 or code == 1 then
      showBrowser()
    end
  end
end

local function eventHandler(typ, address, char, code)
  if typ == "key_down" then handleKeyDown(code) end
end

local function init(dir)
  if not filesystem.exists(dir) or not filesystem.isDirectory(dir) then
    print("Error: Invalid directory: " .. dir)
    os.exit(1)
  end

  app.images = scanDirectory(dir)
  if #app.images == 0 then
    print("No valid CTIF images found.")
    os.exit(1)
  end

  showBrowser()
  event.addHandler(eventHandler)

  while true do
    local signal = {computer.pullSignal()}
    if signal[1] == "exit" then break end
  end
end

local dir = args[1] or "/"
init(dir)