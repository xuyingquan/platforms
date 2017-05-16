local cjson = require "cjson.safe"

local _M = {}

local timedOut = 300

function _M.setConfig(sharedName)

    if ngx.req.get_method() ~= "SET" then
        return nil, 405
    end

    if not ngx.var.arg_sessionid or ngx.var.arg_sessionid == "" then
        return nil, 400
    end

    local argTable = {block = nil, limitrate = nil}

    if ngx.var.arg_block and ngx.var.arg_block == "1" then
        argTable["block"] = ngx.var.arg_block
    elseif ngx.var.arg_limitrate and ngx.var.arg_limitrate ~= "" then
        local limitrate = tonumber(ngx.var.arg_limitrate)
        if limitrate and limitrate > 0 then
            argTable["limitrate"] = limitrate
        end
    else
        return nil, 400
    end

    local valueString = cjson.encode(argTable)

    local dict = ngx.shared[sharedName]

    local ok, err = dict:set(ngx.var.arg_sessionid, valueString, timedOut)
    if not ok then
        return nil, 500
    else
        return true, 200
    end

end

function _M.handle(sharedName)

    local dict = ngx.shared[sharedName]

    local valueString = dict:get(ngx.var.http_x_session_id)
    if valueString then
        local argTable = cjson.decode(valueString)
        dict:delete(ngx.var.http_x_session_id)

        if argTable["block"] == "1" then
            ngx.arg[2] = true
            return ngx.ERROR
        end

        if argTable["limitrate"] and argTable["limitrate"] ~= "" then
            ngx.var.limit_rate = argTable["limitrate"] * 1024
            ngx.var.limit_rate_after = ngx.var.bytes_sent
        end
    end

end

return _M
