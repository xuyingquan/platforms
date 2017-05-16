local request = require "ant.request"

local function handleTsRange()

    if string.match(ngx.var.uri, "%.m3u8$") then
        return true
    end

    if ngx.var.http_range then
        local start_range, end_range = string.match(ngx.var.http_range, "bytes=(%d-)%-(%d-)$")
        start_range = tonumber(start_range)
        end_range   = tonumber(end_range)

        local start_n, end_n

        local argBrs, arg_bre
        argBrs = tonumber(ngx.var.arg_brs) or 0
        argBre = tonumber(ngx.var.arg_bre) or 0

        if start_range == nil or start_range == "" then
            start_n = argBre - end_range
            end_n   = argBre
        elseif end_range == nil or end_range == "" then
            start_n = argBrs + start_range
            end_n   = argBre
        else
            start_n = argBrs + start_range
            local tmp_end = argBrs + end_range
            if tmp_end > argBre then
                end_n = argBre
            else
                end_n = tmp_end
            end
        end
        ngx.req.set_header("Range", "bytes=" .. start_n.. "-" .. end_n)
    else
        ngx.req.set_header("Range", "bytes=" .. ngx.var.arg_brs .. "-" .. ngx.var.arg_bre)
    end

end

local function handleCacheKey()

    local resUri = string.reverse(ngx.var.uri)
    local pos1   = string.find(resUri, "/")
    local pos2   = string.find(resUri, "/", pos1 + 1)

    local vkey   = string.sub(resUri, pos1 + 1, pos2 - 1)
    vkey         = string.reverse(vkey)

    local tsName = string.sub(resUri, 1, pos1)
    tsName       = string.reverse(tsName)

    local uri = ""
    if string.match(ngx.var.uri, "%.ts$") then
        local requestFilename = string.match(tsName, "/%d*_*(.-)%.ts$")
        uri = "/" .. requestFilename .. ".ts"
    else
    	local pos = string.find(tsName, "_")
    	if not pos then
    		uri = tsName
    	else
    		local pre = string.sub(tsName, 2, pos - 1)
    		if tonumber(pre) then
    			local tmpName = string.sub(tsName, pos + 1)
    			uri = "/" .. tmpName
    		else
    			uri = tsName
    		end
    	end

        local s = string.match(ngx.var.ant_auth_info, "start=(%d+)") or ""
        local e = string.match(ngx.var.ant_auth_info, "end=(%d+)")   or ""

        ngx.req.set_header("X-M3u8-Start", s)
        ngx.req.set_header("X-M3u8-End", e)
    end

    --[[
    uri = "/" .. vkey .. uri
    ngx.req.set_uri(uri)
    ]]--

    ngx.req.set_header("X-Cache-Key", ngx.var.host .. uri)

    ngx.var.ant_consistent_key = ngx.var.host .. ngx.var.uri

    return vkey

end

local function handleMp4Seek()

    local args = ngx.req.get_uri_args(0)

    local args_start = tonumber(args["start"])
    local args_end   = tonumber(args["end"])

    local auth_start = tonumber(string.match(ngx.var.ant_auth_info, "start=(%d+)"))
    local auth_end   = tonumber(string.match(ngx.var.ant_auth_info, "end=(%d+)"))

    if not args_start and not args_end then

        if not auth_start then auth_start = 0 end

        if auth_start == 0 and (not auth_end or auth_end == 0) then return true end

        if auth_end == 0 then auth_end = nil end

        args["start"] = auth_start
        args["end"]   = auth_end

        ngx.req.set_uri_args(args)

        return true
    end

    local tmp_start = args_start or auth_start or 0
    local tmp_end   = args_end or auth_end

    if tmp_start < 0 then tmp_start = 0 end

    if tmp_end == 0 then tmp_end = nil end

    if tmp_end and (tmp_end < 0 or tmp_start > tmp_end) then
        ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    args["start"] = tmp_start
    args["end"]   = tmp_end

    ngx.req.set_uri_args(args)

    return true

end

local function authExit()
    if string.match(ngx.var.uri, "%.ts$") or string.match(ngx.var.uri, "%.m3u8$") then
        local vkey, dir, file = string.match(ngx.var.uri, "^(/[^/]*)(.*/)%d*_?([^/]+)$")
        local param = "vkey=" .. (vkey or "") .. "&shataparam=true"

        if ngx.var.args ~= nil and ngx.var.args ~= "" then
            param = ngx.var.args .. "&" .. param
        end

        local sdtfrom = string.match(ngx.var.ant_auth_info or "", "sdtfrom=(%d+)")
        param = param .. "&sdtfrom=" .. (sdtfrom or "")
        ngx.header["X-Request-Uri"] = dir .. file .. "?" .. param

    elseif string.match(ngx.var.uri, "%.mp4$") then
        ngx.header["X-Request-Uri"] = ngx.var.request_uri
    end
end

local function doAccess()

    if string.match(ngx.var.uri, "%.mp4$") then
        if ngx.var.arg_vkey == nil or ngx.var.arg_vkey == "" then
            ngx.exit(ngx.HTTP_FORBIDDEN)
        end
    end

    -- init request, set var label, set session id
    request.initRequest()

    -- do auth request
    local ok = request.authRequest(nil, authExit)
    if ok == false then
        ngx.var.ant_auth_info = ""
    end

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    if request.isFirstNode() then
        local rules = {
            {
                uri = "%.m3u8$",
                value = "hlsgw_backend"
            }
        }

        ngx.header["Client-Ip"] = ngx.var.http_x_remote_addr
        ngx.header["X-ServerIp"] = ngx.var.http_x_server_addr

        request.bodyAuth()

        if string.match(ngx.var.uri, "%.ts$") or string.match(ngx.var.uri, "%.m3u8$") then

            local vkey = handleCacheKey()

            handleTsRange()

            local speed = string.match(ngx.var.ant_auth_info, "speed=(%d+)")
            local limitRate = (tonumber(speed) or 0 ) * 1024
            ngx.var.limit_rate = limitRate

            local param = "vkey=" .. (vkey or "") .. "&shataparam=true"

            if Args ~= nil and Args ~= "" then
                param = Args .. "&" .. param
            end

            local sdtfrom = string.match(ngx.var.ant_auth_info, "sdtfrom=(%d+)")

            param = param .. "&sdtfrom=" .. (sdtfrom or "")

            local vkey, dir, file = string.match(ngx.var.uri, "^(/[^/]*)(.*/)%d*_?([^/]+)$")
            ngx.req.set_uri(vkey .. dir .. file)
            ngx.header["X-Request-Uri"] = dir .. file .. "?" .. param

        elseif string.match(ngx.var.uri, "%.mp4$") then

            handleMp4Seek()

            local speed = string.match(ngx.var.ant_auth_info, "speed=(%d+)")
            local limitRate = (tonumber(speed) or 0 ) * 1024
            ngx.var.limit_rate = limitRate

            ngx.header["X-Request-Uri"] = ngx.var.request_uri

        end

        request.selectUpstream(rules)

        ngx.req.set_header("ISURE-ADDR", ngx.var.http_x_remote_addr)

    end

    -- do redirect
    request.antRedirect()

end

doAccess()
