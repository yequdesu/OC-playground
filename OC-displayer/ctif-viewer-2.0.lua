local component = require("component")
local event = require("event")
local gpu = component.gpu
local os = require("os")
local term = require("term")
local unicode = require("unicode")
local filesystem = require("filesystem")

local args = {...}

function abort(message)
  print("Error: " .. message)
  os.exit(1)
end

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
      abort("Invalid header.")
    end
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

function displayImage(path)
  drawImage(loadImage(path))
end

function resetResolution()
  local x, y = gpu.maxResolution()
  gpu.setResolution(x, y)
end

function clearScreen()
  gpu.setBackground(0, false) -- black bg.
  gpu.setForeground(16777215, false) -- white fg.
  term.clear()
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

function showMenu(images)
  if #images == 0 then
    term.clear()
    term.setCursor(1, 1)
    term.write("No valid CTIF images found in the directory.")
    event.pull(10)  -- timeout after 10 seconds
    return nil
  end

  local selected = 1
  local maxW, maxH = gpu.maxResolution()
  gpu.setResolution(maxW, maxH)
  clearScreen()

  while true do
    term.clear()
    term.setCursor(1, 1)
    term.write("Select an image to display (use arrow keys, Enter to select, ESC to exit):")
    for i, path in ipairs(images) do
      term.setCursor(1, i + 1)
      if i == selected then
        term.write("> " .. filesystem.name(path))
      else
        term.write("  " .. filesystem.name(path))
      end
    end

    local eventType, _, key = event.pull(5)  -- timeout after 5 seconds
    if not eventType then
      term.setCursor(1, #images + 3)
      term.write("No input received within 5 seconds, exiting menu.")
      os.sleep(2)
      return nil
    elseif eventType == "key_down" then
      if key == 200 then -- up
        selected = selected > 1 and selected - 1 or #images
      elseif key == 208 then -- down
        selected = selected < #images and selected + 1 or 1
      elseif key == 28 then -- enter
        return selected
      elseif key == 1 then -- esc
        return nil
      end
    end
    -- ignore other events
  end
end

function main()
  local dir = args[1] or "."
  if not filesystem.exists(dir) or not filesystem.isDirectory(dir) then
    abort("Invalid directory: " .. dir)
  end

  -- Check for keyboard component
  if not component.keyboard then
    abort("No keyboard component found. Please attach a keyboard to the computer.")
  end

  local images = scanDirectory(dir)
  if #images == 0 then
    print("No valid CTIF images found in the directory.")
    return
  end

  local current = showMenu(images)
  if not current then
    return
  end

  while true do
    displayImage(images[current])
    local eventType, _, key = event.pull(30)  -- timeout after 30 seconds
    if not eventType then
      -- timeout, continue showing current image
    elseif eventType == "key_down" then
      if key == 200 then -- up arrow, previous image
        current = current > 1 and current - 1 or #images
      elseif key == 208 then -- down arrow, next image
        current = current < #images and current + 1 or 1
      elseif key == 203 then -- left arrow, return to menu
        resetResolution()
        clearScreen()
        current = showMenu(images)
        if not current then
          break
        end
      end
    end
    -- ignore other events
  end

  resetResolution()
  clearScreen()
end

main()