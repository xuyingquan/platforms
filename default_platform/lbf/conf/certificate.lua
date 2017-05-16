local frame = require "ant.frame"
local ssl = require "ngx.ssl"
local io = require("io")
local lfs = require("lfs")

local function getCertFileTime(fileName)
    fileName = ngx.config.prefix() .. "cert/" .. fileName
    local attr = lfs.attributes(fileName)
    if attr then
        return attr.change
        --return attr.modification
    end
    return nil
end

local function readCertFile(fileName, flag)
    fileName = ngx.config.prefix() .. "cert/" .. fileName
    local cert, err

    local File = io.open(fileName, "r")
    if not File then
        return nil, "cert file open field : " .. fileName
    end

    local Str = File:read("*a")
    if not Str then
        File:close()
        return nil, "cert file is nil : " .. fileName
    end

    File:close()

    if flag then
        cert, err = ssl.cert_pem_to_der(Str)
    else
        cert, err = ssl.priv_key_pem_to_der(Str)
    end

    return cert, err
end

local function loadCertCache(serverName, certName, keyName)
    if not frame.certCache then
        frame.certCache = {}
    end

    local certTime, keyTime
    local now = ngx.time()
    local cert, key, err1, err2

    if not frame.certCache[serverName] then

        frame.certCache[serverName] = {}
        frame.certCache[serverName].lastTime = now
        frame.certCache[serverName].certName = certName
        frame.certCache[serverName].keyName = keyName
        frame.certCache[serverName].certTime = getCertFileTime(certName)
        frame.certCache[serverName].keyTime = getCertFileTime(keyName)
        frame.certCache[serverName].cert, err1 = readCertFile(certName, true)
        frame.certCache[serverName].key, err2 = readCertFile(keyName, false)

    elseif frame.certCache[serverName].lastTime + 5 < now then

        certTime = getCertFileTime(certName)
        keyTime = getCertFileTime(keyName)

        if frame.certCache[serverName].certTime ~= certTime
            or frame.certCache[serverName].keyTime ~= keyTime then

            frame.certCache[serverName].certTime = getCertFileTime(certName)
            frame.certCache[serverName].keyTime = getCertFileTime(keyName)
            frame.certCache[serverName].cert, err1 = readCertFile(certName, true)
            frame.certCache[serverName].key, err2 = readCertFile(keyName, false)

        end

        frame.certCache[serverName].lastTime = now
    end


    cert = frame.certCache[serverName].cert
    key = frame.certCache[serverName].key
    if not cert or not key then
        frame.certCache[serverName] = nil
        return nil, nil, err1 or err2
    end

    return cert, key, err1 or err2
end

function setCertByServerName()
    local servername = ssl.server_name()

    if not servername then
        ngx.log(ngx.CRIT, "ssh get server name error ")
        return ngx.exit(ngx.ERROR)
    end

    if not frame.certs[servername] then
        ngx.log(ngx.CRIT, "frame certs haven't this servername : ", servername)
        return ngx.exit(ngx.ERROR)
    end

    local certName = frame.certs[servername].cert
    local keyName = frame.certs[servername].key

    if not certName or not keyName then
        ngx.log(ngx.CRIT, "cert or key 's filename is nil")
        return ngx.exit(ngx.ERROR)
    end

    local cert, key, err = loadCertCache(servername, certName, keyName)
    if not cert or not key then
        ngx.log(ngx.ERR, err)
        return ngx.exit(ngx.ERROR)
    end

    local ok
    ok, err = ssl.clear_certs()
    if not ok then
        ngx.log(ngx.ERR, "failed to clear existing (fallback) certificates err: ", err)
        return ngx.exit(ngx.ERROR)
    end

    ok, err = ssl.set_der_cert(cert)
    if not ok then
        ngx.log(ngx.ERR, err)
        return ngx.exit(ngx.ERROR)
    end

    ok, err = ssl.set_der_priv_key(key)
    if not ok then
        ngx.log(ngx.ERR, err)
        return ngx.exit(ngx.ERROR)
    end
end

setCertByServerName()
