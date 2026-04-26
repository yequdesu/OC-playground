local json = require("lib.json")

local api = {}

local BASE_URL = "https://api.deepseek.com/chat/completions"

function api.new(apiKey)
  local self = { apiKey = apiKey }
  setmetatable(self, { __index = api })
  return self
end

function api:chat(messages)
  local body = json.encode({
    model = "deepseek-v4-flash",
    messages = messages,
    stream = false
  })

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. self.apiKey
  }

  local internet = require("component").internet
  if not internet then
    return nil, "No internet card found"
  end

  local ok, request = pcall(internet.request, BASE_URL, body, headers, "POST")
  if not ok then
    return nil, "Request failed: " .. tostring(request)
  end
  if not request then
    return nil, "Request returned nil handle"
  end

  local response = ""
  while true do
    local chunk, reason = request.read(math.huge)
    if chunk then
      response = response .. chunk
    else
      request:close()
      if reason then
        return nil, "Read error: " .. tostring(reason)
      end
      break
    end
  end

  if response == "" then
    return nil, "Empty response"
  end

  local data = json.decode(response)
  if not data then
    return nil, "Failed to parse JSON response"
  end

  if data.error then
    return nil, data.error.message or "API error"
  end

  if data.choices and data.choices[1] and data.choices[1].message then
    return data.choices[1].message.content
  end

  return nil, "Unexpected response format"
end

return api