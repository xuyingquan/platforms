local request = require "ant.request"


local function getLimitRate()
    local limitrate = ngx.var.arg_limitrate
    if limitrate == nil or limitrate == "" or limitrate == "0" then
        return tostring(1024 * 1024)
    end

    -- kbps to Bps
    local rate = tonumber(limitrate)
    if not rate then
        ngx.log(ngx.INFO, "illegal limitrate ", limitrate)
        return tostring(1024 * 1024)
    end

    return tostring(rate * 128)
end

local function setCacheInfo()
    function getCacheKey()
        local arange = ""
        if string.find(ngx.var.uri, "%.mp4$") then
            arange = ngx.var.arg_arange or ""
        end

        local key = "pcvideost.titan.imgo.tv" .. ngx.var.uri .. arange
        ngx.var.ant_consistent_key = key
        return key
    end

    ngx.req.set_header("X-Cache-Key", getCacheKey())
    ngx.req.set_header("X-Cache-Division", "mgtv-pcvideost.titan.imgo.tv")
end

local function requestFilter()
    -- if *.xml, return 200
    local uri = ngx.var.uri
    local ok = string.find(uri, "%.xml$")
    if ok then
        return 200
    end

    if ngx.var.arg_fid == "" then
        return 403
    end

    if ngx.var.arg_t == "" then
        return 403
    end

    if ngx.var.arg_uuid == "" then
        return 403
    end

    if ngx.var.arg_srgid == "" then
        return 403
    end

    if ngx.var.arg_srgids == "" then
        return 403
    end

    if ngx.var.arg_nid == "" then
        return 403
    end

    if ngx.var.arg_sign == "" then
        return 403
    end

    if ngx.var.arg_ver == "" then
        return 403
    end

    return 200
end

local function doAccess()

    local res = string.match(ngx.var.uri, "%.m3u8$")
    if res ~= nil and res ~= "" then
        if ngx.var.arg_pm ~= nil then
            ngx.req.set_header("X-Encryption-Args", ngx.var.args)
        end
    end

    -- init request, set var label, set session id
    request.initRequest()

    if ngx.var.arg_pm ~= nil then

        -- do auth request
        if not request.authRequest(3) then
            ngx.exit(ngx.var.status_auth)
        end

        if ngx.var.ant_auth_info ~= nil and ngx.var.ant_auth_info ~= "" then
            ngx.var.args = ngx.var.ant_auth_info
        end

        local pno = ngx.var.arg_pno
        local accountId = "." .. ngx.var.host
        if not pno or pno == "" then
            accountId = "-" .. accountId
        else
            accountId = pno .. accountId
        end

        ngx.header["X-Account-Id"] = accountId

        ngx.header["X-Request-Uri"] = ngx.var.uri .. "?" .. (ngx.var.ant_auth_info or "")
    else
        request.authRequest()
        ngx.header["X-Request-Uri"] = ngx.var.request_uri
    end

    -- set cache info for uce
    setCacheInfo()

    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    if request.isFirstNode() then
        local rules = {
           {
                uri = "%.m3u8$",
                value = "hlsgw_backend"
           },
        }
        -- do pre auth request
        status = requestFilter()
        if status > ngx.HTTP_SPECIAL_RESPONSE then ngx.exit(status) return end

        -- do select upstream
        request.selectUpstream(rules)

        -- set limit rate
        ngx.var.limit_rate = getLimitRate()
    end

    -- do redirect
    request.antRedirect()
end

doAccess()

