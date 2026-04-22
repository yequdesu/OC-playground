local component = require("component")
local gpu = component.gpu
local os = require("os")
local filesystem = require("filesystem")

local args = {...}

function r8(file)
  local byte = file:read(1)
  if byte == nil then
    return 0
  else
    return string.byte(byte) & 255
  end
end

function r16(file)
  local x = r8(file)
  return x | (r8(file) << 8)
end

function gpuBG()
  local a, al = gpu.getBackground()
  if al then
    return gpu.getPaletteColor(a)
  else
    return a
  end
end

function gpuFG()
  local a, al = gpu.getForeground()
  if al then
    return gpu.getPaletteColor(a)
  else
    return a
  end
end

function generatePalette(data)
  local pal = {}

  for i = 0, 255 do
    if (i < 16) then
      if data == nil or data[3] == nil or data[3][i] == nil then
        pal[i] = (i * 15) << 16 | (i * 15) << 8 | (i * 15)
      else
        pal[i] = data[3][i]
        gpu.setPaletteColor(i, data[3][i])
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

function isValidCTIF(filename)
  local file = io.open(filename, 'rb')
  if not file then return false end
  local hdr = {67, 84, 73, 70} -- "CTIF"
  for i = 1, 4 do
    if r8(file) ~= hdr[i] then
      io.close(file)
      return false
    end
  end
  local hdrVersion = r8(file)
  if hdrVersion > 1 then
    io.close(file)
    return false
  end
  local platformVariant = r8(file)
  local platformId = r16(file)
  if platformId ~= 1 or platformVariant ~= 0 then
    io.close(file)
    return false
  end
  io.close(file)
  return true
end

function loadImage(filename)
  local data = {}
  local file = io.open(filename, 'rb')
  local hdr = {67, 84, 73, 70}

  for i = 1, 4 do
    if r8(file) ~= hdr[i] then
      return nil
    end
  end

  local hdrVersion = r8(file)
  local platformVariant = r8(file)
  local platformId = r16(file)

  if hdrVersion > 1 then
    io.close(file)
    return nil
  end

  if platformId ~= 1 or platformVariant ~= 0 then
    io.close(file)
    return nil
  end

  data[1] = {}
  data[2] = {}
  data[3] = {}
  data[2][1] = r8(file)
  data[2][1] = (data[2][1] | (r8(file) << 8))
  data[2][2] = r8(file)
  data[2][2] = (data[2][2] | (r8(file) << 8))

  local pw = r8(file)
  local ph = r8(file)
  if not (pw == 2 and ph == 4) then
    io.close(file)
    return nil
  end

  data[2][3] = r8(file)
  if (data[2][3] ~= 4 and data[2][3] ~= 8) or data[2][3] > gpu.getDepth() then
    io.close(file)
    return nil
  end

  local ccEntrySize = r8(file)
  local customColors = r16(file)
  if customColors > 0 and ccEntrySize ~= 3 then
    io.close(file)
    return nil
  end
  if customColors > 16 then
    io.close(file)
    return nil
  end

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

  io.close(file)
  return data
end

  local hdrVersion = r8(file)
  local platformVariant = r8(file)
  local platformId = r16(file)

  if hdrVersion > 1 then
    abort("Unknown header version: " .. hdrVersion)
  end

  if platformId ~= 1 or platformVariant ~= 0 then
    abort("Unsupported platform ID: " .. platformId .. ":" .. platformVariant)
  end

  data[1] = {}
  data[2] = {}
  data[3] = {}
  data[2][1] = r8(file)
  data[2][1] = (data[2][1] | (r8(file) << 8))
  data[2][2] = r8(file)
  data[2][2] = (data[2][2] | (r8(file) << 8))

  local pw = r8(file)
  local ph = r8(file)
  if not (pw == 2 and ph == 4) then
    abort("Unsupported character width: " .. pw .. "x" .. ph)
  end

  data[2][3] = r8(file)
  if (data[2][3] ~= 4 and data[2][3] ~= 8) or data[2][3] > gpu.getDepth() then
    abort("Unsupported bit depth: " .. data[2][3])
  end

  local ccEntrySize = r8(file)
  local customColors = r16(file)
  if customColors > 0 and ccEntrySize ~= 3 then
    abort("Unsupported palette entry size: " .. ccEntrySize)
  end
  if customColors > 16 then
    abort("Unsupported palette entry amount: " .. customColors)
  end

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

  io.close(file)
  return data
end

function drawImage(data, offx, offy)
  if offx == nil then offx = 0 end
  if offy == nil then offy = 0 end

  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]

  gpu.setResolution(WIDTH, HEIGHT)

  local pal = generatePalette(data)

  local bg = 0
  local fg = 0
  local cw = 1
  local noBG = false
  local noFG = false
  local ind = 1

  local gBG = gpuBG()
  local gFG = gpuFG()

  local unicode = require("unicode")
  local q = {}
  for i = 0, 255 do
    local dat = (i & 0x01) << 7
    dat = dat | (i & 0x02) >> 1 << 6
    dat = dat | (i & 0x04) >> 2 << 5
    dat = dat | (i & 0x08) >> 3 << 2
    dat = dat | (i & 0x10) >> 4 << 4
    dat = dat | (i & 0x20) >> 5 << 1
    dat = dat | (i & 0x40) >> 6 << 3
    dat = dat | (i & 0x80) >> 7
    q[i + 1] = unicode.char(0x2800 | dat)
  end

  for y = 0, HEIGHT - 1 do
    local str = ""
    for x = 0, WIDTH - 1 do
      ind = (y * WIDTH) + x + 1
      if data[2][3] > 4 then
        bg = pal[data[1][ind] & 0xFF]
        fg = pal[(data[1][ind] >> 8) & 0xFF]
        cw = ((data[1][ind] >> 16) & 0xFF) + 1
      else
        fg = pal[data[1][ind] & 0x0F]
        bg = pal[(data[1][ind] >> 4) & 0x0F]
        cw = ((data[1][ind] >> 8) & 0xFF) + 1
      end
      noBG = (cw == 256)
      noFG = (cw == 1)
      if (noFG or (gBG == fg)) and (noBG or (gFG == bg)) then
        str = str .. q[257 - cw]
      elseif (noBG or (gBG == bg)) and (noFG or (gFG == fg)) then
        str = str .. q[cw]
      else
        if #str > 0 then
          gpu.set(x + 1 + offx - unicode.wlen(str), y + 1 + offy, str)
        end
        if (gBG == fg and gFG ~= bg) or (gFG == bg and gBG ~= fg) then
          cw = 257 - cw
          local t = bg
          bg = fg
          fg = t
        end
        if gBG ~= bg then
          gpu.setBackground(bg)
          gBG = bg
        end
        if gFG ~= fg then
          gpu.setForeground(fg)
          gFG = fg
        end
        str = q[cw]
      end
    end
    if #str > 0 then
      gpu.set(WIDTH + 1 - unicode.wlen(str) + offx, y + 1 + offy, str)
    end
  end
end

function scanDirectory(dir)
  local images = {}
  for file in filesystem.list(dir) do
    if string.sub(file, -5) == ".ctif" then
      local fullPath = filesystem.concat(dir, file)
      if isValidCTIF(fullPath) then
        table.insert(images, fullPath)
      end
    end
  end
  return images
end

function resetResolution()
  local x, y = gpu.maxResolution()
  gpu.setResolution(x, y)
end

function clearScreen()
  gpu.setBackground(0, false)
  gpu.setForeground(16777215, false)
  local term = require("term")
  term.clear()
end

-- Main Program
local dir = args[1] or "."
if not filesystem.exists(dir) or not filesystem.isDirectory(dir) then
  print("Error: Invalid directory: " .. dir)
  os.exit(1)
end

local images = scanDirectory(dir)
if #images == 0 then
  print("No valid CTIF images found.")
  os.exit(1)
end

-- App State
local appState = {
  mode = "menu",  -- "menu" 或 "view"
  currentIndex = 1,
  images = images,
  menuIndex = 1
}

local function showMenu()
  resetResolution()
  clearScreen()
  
  local term = require("term")
  local maxW, maxH = gpu.maxResolution()
  gpu.setResolution(maxW, maxH)
  
  term.setCursor(1, 1)
  term.write("CTIF Image Viewer - Select Image")
  term.setCursor(1, 2)
  term.write("================================")
  
  local startIndex = math.max(1, appState.menuIndex - 10)
  local endIndex = math.min(#images, startIndex + 20)
  
  for i = startIndex, endIndex do
    local displayRow = i - startIndex + 4
    term.setCursor(1, displayRow)
    
    if i == appState.menuIndex then
      term.write("> ")
    else
      term.write("  ")
    end
    
    term.write(filesystem.name(images[i]))
  end
  
  local _, maxHeight = gpu.maxResolution()
  term.setCursor(1, maxHeight)
  term.write("UP/DOWN: navigate | ENTER: view | LEFT: exit")
end

local function showImage(imageIndex)
  appState.mode = "view"
  local imageData = loadImage(images[imageIndex])
  
  if imageData then
    drawImage(imageData)
  end
end

local function handleMenuKeyDown(keyboard, code)
  if code == 200 then -- UP
    appState.menuIndex = appState.menuIndex > 1 and appState.menuIndex - 1 or #images
  elseif code == 208 then -- DOWN
    appState.menuIndex = appState.menuIndex < #images and appState.menuIndex + 1 or 1
  elseif code == 28 then -- ENTER
    appState.currentIndex = appState.menuIndex
    showImage(appState.currentIndex)
  elseif code == 1 then -- ESC
    os.exit(0)
  end
end

local function handleViewKeyDown(keyboard, code)
  if code == 200 then -- UP
    appState.currentIndex = appState.currentIndex > 1 and appState.currentIndex - 1 or #images
    showImage(appState.currentIndex)
  elseif code == 208 then -- DOWN
    appState.currentIndex = appState.currentIndex < #images and appState.currentIndex + 1 or 1
    showImage(appState.currentIndex)
  elseif code == 203 then -- LEFT
    appState.mode = "menu"
    appState.menuIndex = appState.currentIndex
    showMenu()
  end
end

-- Menu Start
showMenu()

-- Event Loop
local event = require("event")
while true do
  local eventType, keyboard, code = event.pull(1)
  
  if eventType == "key_down" then
    if appState.mode == "menu" then
      handleMenuKeyDown(keyboard, code)
      showMenu()
    elseif appState.mode == "view" then
      handleViewKeyDown(keyboard, code)
      if appState.mode == "menu" then
        showMenu()
      end
    end
  end
end
