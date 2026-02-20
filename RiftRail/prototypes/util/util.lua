local util = {}
function util.create_centered_box(w, h)
    local hw = w / 2
    local hh = h / 2
    return { { -hw, -hh }, { hw, hh } }
end

function util.table_merge(dest, src)
    for k, v in pairs(src) do dest[k] = v end
    return dest
end

return util
