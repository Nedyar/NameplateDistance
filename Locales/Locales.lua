-- Locales: the addon's texts in the client's language (GetLocale).
--
-- The English text is the key, so the code reads in English and any text a
-- language file lacks shows in English. Each language file fills in only its
-- own language. The client has no Japanese; enGB uses the English texts and
-- ptPT the Brazilian Portuguese ones.
local _, ns = ...

local locale = GetLocale()
ns.LOCALE = ({ enGB = "enUS", ptPT = "ptBR" })[locale] or locale

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
