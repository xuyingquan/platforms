local frame = require "ant.frame"
local lfs = require("lfs")
local io = require("io")

local _M = {}

local function walkTree (path, callback)
    local ok, iter, entries = pcall(lfs.dir, path)
    if not ok then return false end

    for file in iter, entries do
        if file ~= "." and file ~= ".." then
            local f = path..'/'..file
            local attr = lfs.attributes (f)
            if attr then
                if attr.mode == "directory" then
                    walkTree (f, callback)
                elseif attr.mode == "file" then
                    callback (f)
                end
            end
        end
    end
    return true
end

function loadCertConfig(conf)
    -- match cert_channel.conf
    if not string.match(conf, "/cert_[^/]+%.conf$") then
        return false
    end

    local file = io.open(conf, "r")
    if not file then 
        ngx.log(ngx.CRIT, "Open ", conf, " Error !!!")
        return false
    end

    for line in file:lines() do
        local domain, cert, key = string.match(line, "^%s-(%S+)%s+(%S+)%s+(%S+)%s-$")   
        if domain and cert and key then
            frame.certs[domain] = {cert = cert, key = key}
        else
            -- skip empty lines
            if string.match(line, "%S") then
                ngx.log(ngx.CRIT, "Load SSL Cert ERROR!! file: ", conf, " line: ", line)
            end
        end
    end
    file:close()

    return true
end

function _M.load()
    frame.certs = {}
    local rootdir = ngx.config.prefix() .. "../../"

    walkTree(rootdir, loadCertConfig)
end

return _M
