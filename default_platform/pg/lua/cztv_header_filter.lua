local request = require "ant.request"

local cacheValidTable = {
    {key = "^/mp4/", time = 2592000},  
    {key = "^/mp5/", time = 86400},  

    {key = "%.ts$", time = 2592000},  
    {key = "%.m3u8$", time = 10},
};

function setCacheControl(tab)
    for i = 1, #tab do
        if string.match(ngx.var.uri, tab[i].key) then
            ngx.header["Cache-Control"] = "max-age=" .. tab[i].time
            break
        end
    end
end

function setHeaders()
    if not ngx.header["My-Header"] then
        ngx.header["My-Header"] = "my_header"
    end
end

function  doHeaderFilter()
    setHeaders()
    setCacheControl(cacheValidTable)
end

doHeaderFilter()
