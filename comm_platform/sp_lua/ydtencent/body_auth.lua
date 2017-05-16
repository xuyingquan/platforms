local request = require "ant.request"

local timeOut = 300

local function handle(pos, bodyLine)
    local dict = ngx.shared.bodyauth

    local tsName = string.sub(bodyLine, 1, pos - 1)
    local args   = string.sub(bodyLine, pos + 1)

    local ok, err = dict:set(tsName, args, timeOut)
    if not ok then ngx.log(ngx.ERR, "shared set failed : ", err) return false end

end

local function bodyFilter()

    if ngx.status ~= ngx.HTTP_OK then
        ngx.ctx.m3u8_flag = "yes"
    end

    local bodyEnd = (ngx.ctx.tmpBody or "") .. (ngx.arg[1] or "")

    while true do
        local pos = string.find(bodyEnd, "\n")
        if not pos then break end

        local bodyLine = string.sub(bodyEnd, 1, pos - 1)
        bodyEnd   = string.sub(bodyEnd, pos + 1)

        local ps = string.find(bodyLine, "?")
        if ps ~= nil then handle(ps, bodyLine) end

    end

    ngx.ctx.tmpBody = bodyEnd

end

bodyFilter()
