
local request = require "ant.request"

local function handleRange()

    if not ngx.var.http_range or ngx.var.http_range == "" then
        return
    end

    local range = string.lower(ngx.var.http_range)
    local s, e  = string.match(range, "bytes=%s*(%d*)%s*%-%s*(%d*)")
    if not s or s == "" or not e or e == "" then
        return
    end

    if tonumber(s) > tonumber(e) then
        ngx.req.clear_header("Range")
    end

end

local function doAccess()

    -- init request, set var label, set session id
    request.initRequest()

    -- do auth request
    request.authRequest()

    if request.isFirstNode() then

        if not ngx.var.ant_auth_info then
            ngx.var.ant_auth_info = ""
        end

        local speed = string.match(ngx.var.ant_auth_info, "speed=(%d*)")
        local limitRate = (tonumber(speed) or 0 ) * 1024

        ngx.var.limit_rate = limitRate

        local cookie = ngx.req.get_headers()["Cookie"]

        local param = "shataparam=true"

        local sdtfrom = ngx.var.arg_fromtag
        if not sdtfrom then
            if not cookie then
                sdtfrom = "999"
            else
                sdtfrom = string.match(cookie, "qqmusic_fromtag=(%d*)")
            end
            if not sdtfrom then sdtfrom = "999" end

            param = param .. "&sdtfrom=" .. sdtfrom
        end

        local Uin = ngx.var.arg_uin
        if not Uin then
            if not cookie then
                Uin = "-"
            else
                Uin = string.match(cookie, "qqmusic_uin=(%d*)")
            end
            if not Uin then Uin = "-" end

            param = param .. "&uin=" ..Uin
        end

        local Guid = ngx.var.arg_guid
        if not Guid then
            if not cookie then
                Guid = "-"
            else
                Guid = string.match(cookie, "qqmusic_guid=(%w*)")
            end
            if not Guid then Guid = "-" end

            param = param .. "&guid=" .. Guid
        end

        if ngx.var.args ~= nil and ngx.var.args ~= "" then
            param = "&" ..param
        end

        ngx.header["X-Request-Uri"] = ngx.var.uri .. "?" .. ngx.var.args .. param

        if sdtfrom == "999" then ngx.exit(403) end

        request.selectUpstream({})

        ngx.req.set_header("ISURE-ADDR", ngx.var.http_x_remote_addr)
    end

    -- do redirect
    request.antRedirect()

    -- range
    handleRange()

end

doAccess()
