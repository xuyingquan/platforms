local request = require "ant.request"

local function setCacheInfo()
    function getCacheKey()
        -- m3u8 cache key
        if string.match(ngx.var.uri, "%.m3u8$") then
            local key = ngx.var.host .. ngx.var.uri .. (ngx.var.arg_video or "") .. "/" .. (ngx.var.arg_audio or "") .. "/" .. (ngx.var.arg_playback or "")
            ngx.var.ant_consistent_key = key
            return key

        -- ts cache key
        elseif string.match(ngx.var.uri, "%.ts$") then
            local key = ngx.var.host .. ngx.var.uri .. (ngx.var.arg_video or "") .. "/" .. (ngx.var.arg_audio or "")
            ngx.var.ant_consistent_key = key
            return key
        else
            return nil
        end
    end
    ngx.req.set_header("X-Cache-Key", getCacheKey())
end

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    -- set cache key for uce
    setCacheInfo()

    -- do auth request
    request.authRequest()

    -- do redirect
    request.antRedirect()

end

doAccess()
