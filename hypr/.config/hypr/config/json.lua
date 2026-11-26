-- Minimal JSON decoder (objects, arrays, strings, numbers, true/false/null).
-- Used to read config/hyprliquid.json, which the Glass Tuner window writes.
-- json.decode(str) -> value, or nil + error message.

local M = {}

local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decode(s)
    local pos = 1

    local function fail(msg)
        error(("json: %s at position %d"):format(msg, pos), 0)
    end

    local function ws()
        pos = s:find("[^ \t\r\n]", pos) or (#s + 1)
    end

    local value

    local function str()
        pos = pos + 1 -- opening quote
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == "" then fail("unterminated string") end
            if c == '"' then pos = pos + 1; break end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                if e == "u" then
                    local hex = s:sub(pos + 2, pos + 5)
                    if not hex:match("^%x%x%x%x$") then fail("bad \\u escape") end
                    out[#out + 1] = utf8.char(tonumber(hex, 16))
                    pos = pos + 6
                elseif ESC[e] then
                    out[#out + 1] = ESC[e]
                    pos = pos + 2
                else
                    fail("bad escape")
                end
            else
                local stop = s:find('["\\]', pos) or (#s + 1)
                out[#out + 1] = s:sub(pos, stop - 1)
                pos = stop
            end
        end
        return table.concat(out)
    end

    local function num()
        local m = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if not m or m == "" then fail("bad number") end
        pos = pos + #m
        return tonumber(m) or fail("bad number")
    end

    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local obj = {}
            ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
            while true do
                ws()
                if s:sub(pos, pos) ~= '"' then fail("expected key") end
                local k = str()
                ws()
                if s:sub(pos, pos) ~= ":" then fail("expected ':'") end
                pos = pos + 1
                obj[k] = value()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return obj end
                if d ~= "," then fail("expected ',' or '}'") end
            end
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
            while true do
                arr[#arr + 1] = value()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return arr end
                if d ~= "," then fail("expected ',' or ']'") end
            end
        elseif c == '"' then
            return str()
        elseif s:sub(pos, pos + 3) == "true" then
            pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == "false" then
            pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == "null" then
            pos = pos + 4; return nil
        else
            return num()
        end
    end

    local v = value()
    ws()
    if pos <= #s then fail("trailing data") end
    return v
end

function M.decode(s)
    local ok, v = pcall(decode, s)
    if ok then return v end
    return nil, v
end

function M.read(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local s = f:read("a")
    f:close()
    return M.decode(s)
end

return M
