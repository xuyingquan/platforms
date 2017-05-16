local request = require "ant.request"

request.setServiceHeader()

if ngx.status >= 400 then
    -- length of "Http Error status xxx"
    ngx.header["Content-Length"] = 21 
end

ngx.header["X-Channel-Id"] = nil
ngx.header["X-Account-Id"] = nil
ngx.header["X-Request-Uri"] = nil

ngx.header["X-Info-Fetcher"]    = nil
ngx.header["X-Info-ObjSize"]    = nil
ngx.header["X-Info-request-id"] = nil

if request.isFirstNode() and ngx.header["X-File-Size"] then
    local filesize = ngx.header["X-File-Size"]
    ngx.header["X-File-Size"] = nil

    local cr = ngx.header["Content-Range"]
    if cr == nil or cr == "" then
        return true;
    end

    ngx.header["Content-Range"] = string.gsub(cr, "/(%d+)$", "/" .. filesize)
end
