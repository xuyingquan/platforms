local request = require "ant.request"
local frame = require "ant.frame"

local function doAccess()

    ngx.var.ant_proxy_proto = "http://"

    local upstreams = frame.env.upstreams
    if upstreams and next(upstreams) then
        if upstreams[1].https == true then
            ngx.var.ant_proxy_proto = "https://"
        end
    end

    -- init request, set var label, set session id
    request.initRequest()

    -- init cache key, cache lock, cache lock age, cache lock timeout
    request.initCacheInfo()

    -- do select upstream
    request.selectUpstream({})
end

doAccess()
