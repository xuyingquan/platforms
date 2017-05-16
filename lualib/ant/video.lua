
local _M = {}

function _M.commSeekOffset(start_offset, end_offset)
    local start_offset_n = tonumber(start_offset or "0") or 0
    local end_offset_n = tonumber(end_offset or "-1") or -1

    if start_offset_n == 0 and end_offset_n == -1 then
        return false
    end

    if ngx.var.http_range then 
        local start_range, end_range = string.match(ngx.var.http_range, "bytes=(%d+)-(%d-)$")
        local start_range_n = tonumber(start_range or "0") or 0
        local end_range_n = tonumber(end_range or "-1") or -1

        if start_range_n > start_offset_n then
            start_offset_n = start_range_n
        end

        if (end_range_n ~= -1 and end_range_n < end_offset_n) or end_offset_n == -1 then
            end_offset_n = end_range_n
        end
    end

    if end_offset_n == -1 then 
        end_offset_n = ""
    end

    ngx.req.set_header("Range", "bytes=" .. start_offset_n .. "-" .. end_offset_n)
    return true
end

function _M.videoDropArgs( drop )
    local args = ngx.req.get_uri_args()

    if type(drop) == "table" then
        for _, v in ipairs(drop) do
            args[v] = nil
        end
    else
        args[drop] = nil
    end

    ngx.req.set_uri_args(args)
end

return _M
