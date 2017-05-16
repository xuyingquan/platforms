local request = require "ant.request"
request.setCacheHeader()

if ngx.req.get_method() == "PURGE" then
    if ngx.header["X-Purge-Result"] then
        ngx.status = ngx.HTTP_OK
    end
end

