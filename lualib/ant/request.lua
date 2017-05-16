-- request.lua

local frame = require "ant.frame"

local getLabel = frame.getLabel
local getNode = frame.getNode
local getSessionID = frame.getSessionID

_M = {}

local function necAuth()

    local necKey = " zhongju"

    local necInfo          = ngx.req.get_headers()["X-Nec-Info"]

    local necMd5           = string.match(necInfo, "md5=([%w_-]*)")
    local necExpiresString = string.match(necInfo, "expires=(%d+)")

    if necExpiresString == nil or necExpiresString == "" or necMd5 == nil or necMd5 == "" then
        ngx.log(ngx.ERR, "nec header error, X-Nec-Info: " .. necInfo)
        return false
    end

    local necExpires = tonumber(necExpiresString)
    local timeNow    = ngx.time()

    if timeNow > necExpires then
        ngx.var.status_auth = ngx.HTTP_UNAUTHORIZED
        ngx.exit(ngx.var.status_auth)
    end

    local necUrl       = ngx.var.scheme .. "://" .. ngx.var.host .. ngx.var.request_uri
    local tempUrl      = ngx.encode_args({url = necUrl})
    local encodeNecUrl = string.match(tempUrl, "url=(.*)")

    local necString = necExpires .. encodeNecUrl .. necKey
    local md5 = ngx.encode_base64(ngx.md5_bin(necString))
    md5 = string.gsub(md5, "/", "_")
    md5 = string.gsub(md5, "+", "-")
    md5 = string.gsub(md5, "=", "")

    if md5 == necMd5 then
        ngx.var.status_auth = ngx.HTTP_OK
    else
        ngx.var.status_auth = ngx.HTTP_UNAUTHORIZED
        ngx.exit(ngx.var.status_auth)
    end

    return true

end

function _M.tsAuth()

    local dict = ngx.shared.bodyauth

    local valueString, err = dict:get(ngx.ctx.tsName)

    if not valueString then
        if err then ngx.log(ngx.ERR, "shared dict get failed : ", err) end
        return false
    end

    local cStart = string.match(valueString, "start=(%d+)") or -1
    local cEnd   = string.match(valueString, "end=(%d+)")   or -1
    local cBrs   = string.match(valueString, "brs=(%d+)")   or -1
    local cBre   = string.match(valueString, "bre=(%d+)")   or -1

    if cStart == ngx.ctx.fStart and cEnd == ngx.ctx.fEnd and cBrs == ngx.ctx.fBrs and cBre == ngx.ctx.fBre then
        ngx.ctx.m3u8_flag = "yes"
    else
        ngx.ctx.m3u8_flag = "no"
    end 

    return true  

end

function _M.bodyAuth()
    local ok = string.match(ngx.var.uri, "%.ts$")
    if ok == nil or ok == "" then
        return true
    end

    local uri = string.reverse(ngx.var.uri)
    local pos = string.find(uri, "/")

    local prefix = string.sub(uri, pos)
    local tsName = string.sub(uri, 1, pos-1)

    prefix = string.reverse(prefix)
    tsName = string.reverse(tsName)

    local tmpName  = string.match(tsName, "%d*_*(.-)%.?%d*%.ts$")
    local m3u8Name = tmpName .. ".ts.m3u8"

    ngx.ctx.fStart = ngx.var.arg_start;
    ngx.ctx.fEnd   = ngx.var.arg_end;
    ngx.ctx.fBrs   = ngx.var.arg_brs;
    ngx.ctx.fBre   = ngx.var.arg_bre;

    ngx.ctx.tsName = tsName

    ngx.ctx.m3u8_flag = ""

    if _M.tsAuth() == false then

        local m3u8_uri = frame.listen.hsm[1] .. prefix .. m3u8Name
        ngx.req.set_header("X-M3u8-Uri", m3u8_uri)

        local res = ngx.location.capture("/bodyauth", {ctx = ngx.ctx})

        ngx.req.clear_header("X-M3u8-Uri")
    end

    if ngx.ctx.m3u8_flag == "no" then
        ngx.exit(ngx.HTTP_FORBIDDEN)
    end

end

function _M.authRequest(retries, onExit)
    if not _M.isFirstNode() then
        return true
    end
    --  auth once for run access phase more
    if ngx.var.status_auth == nil or  ngx.var.status_auth ~= "" then
        return true
    end

    if frame.env.disable_auth then return true end

    if ngx.req.get_method() == "PURGE" then
        return true
    end

    -- do nec access
    if ngx.req.get_headers()["X-Nec-Info"] then
        return necAuth();
    end

    auth_location = ngx.var.ant_auth
    if auth_location == nil or auth_location == "off" or auth_location == ""  then
        return true
    end

    ngx.req.read_body()

    if retries == nil or retries == 0 then
        retries = 1
    end

    for i=1, retries do
        local res = ngx.location.capture(auth_location, {ctx = ngx.ctx, copy_all_vars = true,})
        ngx.var.status_auth  = res.status

        ngx.var.ant_auth_info = res.header["X-Auth-Info"]

        if res.status == ngx.HTTP_UNAUTHORIZED or res.status == ngx.HTTP_FORBIDDEN then
            ngx.log(ngx.INFO, " auth request failed, status ", res.status)
            if onExit then
                onExit()
            else
                ngx.header["X-Request-Uri"] = ngx.var.request_uri
            end
            ngx.exit(res.status)
        end

        if res.status ~= 0 and res.status < 500 then
            return true
        end
    end

    return false
end

function _M.antRedirect()

    local hrb_sid_interval = 60
    local redirect_location = ngx.var.ant_redirect
    if redirect_location == nil or redirect_location == "off" or redirect_location == ""  then
        return true
    end

    if frame.env.disable_precise then return true end

    if ngx.req.get_method() == "PURGE" then
        return true
    end

    if ngx.var.http_x_redirect_twice then
        return true
    end

    local ck = require "ant.cookie"
    local cookie, err = ck:new()
    if not cookie then
        ngx.log(ngx.INFO, err)
        return true
    end

    local hrb_sid, err = cookie:get("__hrb_sid")
    if hrb_sid then
        local sid = ngx.decode_base64(hrb_sid)
        if sid then
            local addr, ts = string.match(sid, "(.-);(%d+)")
            if addr == (ngx.var.http_x_server_addr or ngx.var.server_addr) and ts ~= nil and tonumber(ts) <= ngx.time() and tonumber(ts) + hrb_sid_interval > ngx.time() then
                return true
            end
        end
    end

    ngx.req.read_body()

    local res = ngx.location.capture(redirect_location, {ctx = ngx.ctx, copy_all_vars = true,})
    if res.status ~= ngx.HTTP_MOVED_TEMPORARILY then
        return true
    end

    local redirect_to = res.header["Location"]
    if type(redirect_to) == "table" then
        for _, v in pairs(redirect_to) do
            if v ~= "" then redirect_to = v break end
        end
    end

    if not redirect_to then
        ngx.log(ngx.ERR, " Hrb response location nil !! ")
        return false
    end

    if redirect_to == (ngx.var.http_x_server_addr or ngx.var.server_addr) then
        return true
    end

    local sid = ngx.encode_base64(redirect_to .. ";" .. ngx.time())
    local ok, err = cookie:set({
        key = "__hrb_sid", value = sid, path = "/",
        domain = ngx.var.host, max_age = hrb_sid_interval,
    })

    if not ok then
        ngx.log(ngx.ERR, " set cookie __hrb_sid failed !!! ")
        return false
    end

    ngx.header["Location"] = { "http://" .. redirect_to .. "/" .. ngx.var.host .. ngx.var.uri .. ngx.var.is_args .. (ngx.var.args or "") }
    ngx.exit(res.status)
    return true
end

function _M.necRedirect(cacheKey)

    if ngx.req.get_method() == "PURGE" then
        return true
    end

    if ngx.req.get_headers()["X-Nec-Info"] then
        ngx.req.clear_header("X-Nec-Info")
        return true
    end

    local necUrl = ngx.var.scheme .. "://" .. ngx.var.host .. ngx.var.request_uri

    ngx.var.ant_necurl = ngx.encode_args({url = necUrl, key = cacheKey})

    local nec_location = "/necdispatch"
    local res = ngx.location.capture(nec_location, {ctx = ngx.ctx, copy_all_vars = true})

    if res.status ~= ngx.HTTP_MOVED_TEMPORARILY then
        ngx.log(ngx.INFO, "NEC capture return Wrong Http Code: " .. res.status)
        return true
    end

    local necLocation = res.header['Location']
    if necLocation == nil or necLocation == "" then
        ngx.log(ngx.ERR, "NEC Location response nil")
        return false
    end

    local necAccountId = ngx.var.ant_account_id
    if necAccountId == nil or necAccountId == "" then
        necAccountId = ngx.var.host
    end

    ngx.header['Location'] = { necLocation .. "&channel=" .. ngx.var.channel .. "&session=" .. ngx.var.http_x_session_id .. "&account=" .. necAccountId }

    ngx.exit(res.status)

end

local function simpleFilter()
    local m, err = string.match(ngx.var.uri, "%.m3u8$")
    return m
end

function _M.necJudge(cacheKey)
    local ok, err = simpleFilter()
    if ok then
        return false
    end

    local key = ngx.var.host .. ngx.var.uri .. cacheKey

    local necDictL1 = ngx.shared.necCacheL1
    local necDictL2 = ngx.shared.necCacheL2
    local maxSize = 3

    local keyLen = string.len(key)
    key = keyLen .. ngx.encode_base64(ngx.md5_bin(key))

    local ok, err = necDictL2:get(key)
    if ok then
        return true
    end

    local newval, err = necDictL1:incr(key, 1, 0)
    if newval then
        if newval >= maxSize then
            local ok, err = necDictL2:set(key, true)
            if ok then
                necDictL1:delete(key)
            end
            return true
        end
    end

    return false
end

function _M.initCacheInfo( )
    -- set default proxy cache
    if ngx.var.http_x_proxy_cache == nil or ngx.var.http_x_proxy_cache == "" then
        ngx.var.ant_proxy_cache = "data_" .. ngx.var.server_port
    else
        ngx.var.ant_proxy_cache = ngx.var.http_x_proxy_cache
    end

    -- set default cache key
    if ngx.var.http_x_cache_key == nil or ngx.var.http_x_cache_key == "" then
        ngx.var.ant_cache_key = ngx.var.host .. ngx.var.uri
        ngx.req.set_header("X-Cache-Key", ngx.var.ant_cache_key)
    else
        ngx.var.ant_cache_key = ngx.var.http_x_cache_key
    end

    -- set default cache division
    if ngx.var.http_x_cache_division == nil or ngx.var.http_x_cache_division == "" then
        ngx.var.ant_cache_division = ngx.var.channel
        ngx.req.set_header("X-Cache-Division", ngx.var.ant_cache_division)
    else
        ngx.var.ant_cache_division = ngx.var.http_x_cache_division
    end

    if ngx.var.ant_cache_division == nil or ngx.var.ant_cache_division == "" then
        ngx.log(ngx.ERR, "channel and division missed")
    end

    -- set cache lock
    if ngx.var.http_x_cache_lock ~= nil and ngx.var.http_x_cache_lock ~= "" then
        ngx.var.proxy_cache_lock = ngx.var.http_x_cache_lock
    end

    -- set cache lock age
    if ngx.var.http_x_lock_age ~= nil and ngx.var.http_x_lock_age ~= "" then
        ngx.var.proxy_cache_lock_age = ngx.var.http_x_lock_age
    end

    -- set cache lock timeout
    if ngx.var.http_x_lock_timeout ~= nil and ngx.var.http_x_lock_timeout ~= "" then
        ngx.var.proxy_cache_lock_timeout = ngx.var.http_x_lock_timeout
    end

    -- set cache forwarded
    local x_forwarded_cache = getLabel() .. "(" .. ngx.var.server_addr .. ":" .. ngx.var.server_port .. ")"
    if ngx.var.http_x_forwarded_cache ~= nil and ngx.var.http_x_forwarded_cache ~= "" then
        ngx.req.set_header("X-Forwarded-Cache", ngx.var.http_x_forwarded_cache .. ", " .. x_forwarded_cache)
    else
        ngx.req.set_header("X-Forwarded-Cache", x_forwarded_cache)
    end

    -- set limit rate
    if ngx.var.http_x_limit_rate ~= nil and ngx.var.http_x_limit_rate ~= "" then
        ngx.var.limit_rate = ngx.var.http_x_limit_rate
    end

    -- set limit rate after
    if ngx.var.http_x_limit_rate_after ~= nil and ngx.var.http_x_limit_rate_after ~= "" then
        ngx.var.limit_rate_after = ngx.var.http_x_limit_rate_after
    end

end

function _M.isFirstNode( )
    return (ngx.var.http_x_forwarded_cache == nil or ngx.var.http_x_forwarded_cache == "")
end

function _M.initRequest( )
    -- set label to var
    ngx.var.label = getLabel()

    -- set node to var
    ngx.var.node = getNode()

    -- set channel
    if ngx.var.http_x_channel then
        ngx.var.channel = ngx.var.http_x_channel
    end

    -- set default upstream
    if ngx.var.ant_upstream == "" then
        ngx.var.ant_upstream = "default_backend"
    end

    -- set default consistent hash key
    if ngx.var.ant_consistent_key == "" then
        ngx.var.ant_consistent_key = ngx.var.host .. ngx.var.uri
    end

    -- set session to http header
    if ngx.var.http_x_session_id == nil or ngx.var.http_x_session_id == "" then
        local session_id = getSessionID()
        if session_id then
            ngx.req.set_header("X-Session-Id", session_id)
        end
    end

    -- set channel and account for lbf at hsm
    if frame.product == "HSM" then
        ngx.header["X-Channel-Id"] = ngx.var.channel
        if ngx.var.ant_account_id and ngx.var.ant_account_id ~= "" then
            ngx.header["X-Account-Id"] = ngx.var.ant_account_id
        end
    end
end

local function headerMatch(rules)
    for _, ht in ipairs(rules) do
        local hds = nil
        local key = nil

        if ht.method then
            hds = ngx.req.get_method()
            key = ht.method
        elseif ht.uri then
            hds = ngx.var.uri
            key = ht.uri
        elseif ht.request then
            hds = ngx.req.get_headers()[ht.request]
            key = ht.key
        end

        if hds and key then
            if type(hds) == "table" then
                hds = hds[1]
            end
            if type(key) == "table" then
                for _, keyi in ipairs(key) do
                    if string.match(hds, keyi) then
                        return ht.value
                    end
                end
            elseif string.match(hds, key) then
                return ht.value
            end
        end
    end

    return nil
end

--[[  rule excamples:
    {
        method = "HEAD",
        value = "value",
    },

    {
        request = "Host",
        key = "baidu$",
        -- value = nil
    },

    {
        request = "Host",
        key = {"baidu$", "google$"},
        value = "value"
    },

    {
        uri = "test.txt",
        value = "value",
    },
--]]

function _M.getPurgeUpstream()
    local hc = require "resty.upstream.healthcheck"
    local hcinfo = hc.status_page()

    for i = 1, #frame.listen.uce do
        if string.match(hcinfo, frame.listen.uce[i] .. "%s+up") then
            ngx.var.ant_upstream = frame.listen.uce[i]
            return true
        end
    end

    ngx.var.ant_upstream = frame.listen.uce[1]
    return true
end

function _M.selectUpstream(rules)
    local value = headerMatch(rules)
    if  value then
        ngx.var.ant_upstream = value
        return true
    end

    return false
end

function _M.setCacheHeader()
    local cache_status = ngx.var.upstream_cache_status
    if cache_status then
        if cache_status ~= "HIT" and ngx.header["Via"] then
            ngx.header["Via"]  = getLabel() .. "." .. ngx.var.server_port .. " (" .. cache_status .. "), " .. ngx.header["Via"]
        else
            ngx.header["Via"]  = getLabel() .. "." .. ngx.var.server_port .. " (" .. cache_status .. ")"
        end
    else
        ngx.header["Via"]  = getLabel() .. "." .. ngx.var.server_port
    end

    ngx.header["Age"] = ngx.var.cache_age
end

function _M.statusExpire()

    if not ngx.var.ant_status_expire or ngx.var.ant_status_expire == "" then
        return true
    end

    local expire, rate = string.match(ngx.var.ant_status_expire, "status=" .. ngx.status .. "%s+expire=(%d+)(%a?)")
    if expire == "" or not expire then
        return true
    end
    if rate == "" or not rate then
        rate = 's'
    end

    local time = { s = 1, m = 60, h = 3600, d = 86400 }
    expire = expire * time[rate]

    if ngx.header["Cache-Control"] then
        if ngx.header["Cache-Control"] == "no-cache" then
            return true
        end

        local Texpire = string.match(ngx.header["Cache-Control"], "max%-age=(%d+)")
        if not Texpire or Texpire == "" then
            return true
        end

        local expireNum = tonumber(Texpire)

        if expireNum <= expire then
            return true
        end
    end

    if expire == 0 then
        ngx.header["Cache-Control"] = "no-cache"
    else
        ngx.header["Cache-Control"] = "max-age=" .. expire
    end

end

function _M.getMse()
    if frame.env.mse_map then
        local mse = frame.env.mse_map[ngx.var.server_port]
        if mse then
            return mse.ip or frame.env.mse_ip, mse.port or ngx.var.server_port
        end
    end

    return frame.env.mse_ip, ngx.var.server_port
end

function _M.setServiceHeader()
    ngx.header["Server"] = frame.version
end

return _M
