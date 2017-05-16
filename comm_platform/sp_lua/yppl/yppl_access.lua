local request = require "ant.request"

local function setCacheInfo()
    if string.match(ngx.var.uri, "%.m3u8$") then
        return nil
    else
        function getCacheKey()
            local A = string.match(ngx.var.arg_ext, "A=(%d*)")
            local B = string.match(ngx.var.arg_ext, "B=(%d*)")
            local C = string.match(ngx.var.arg_ext, "C=(%d*)")
            local D = string.match(ngx.var.arg_ext, "D=(%d*)")
            local qtype = string.match(ngx.var.arg_ext, "qtype=(%d*)")

            local key = ngx.var.host .. "/" .. ngx.var.arg_fid .. "A=" .. A .. "B=" .. B .. "C=" .. C .. "D=" .. D .. "qtype=" .. qtype
            ngx.var.ant_consistent_key = key
            return key
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
    if not request.authRequest(3) then
        ngx.exit(ngx.var.status_auth)
    end

    -- do redirect
    request.antRedirect()

end

doAccess()
