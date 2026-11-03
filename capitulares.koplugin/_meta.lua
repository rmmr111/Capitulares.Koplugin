-- Localize plugin title at KOReader startup (no extra translation catalogs).
local locale = G_reader_settings and G_reader_settings:readSetting('language') or 'en'
local pt = type(locale)=='string' and locale:lower():match('^pt')~=nil
return {
    name='capitulares',
    fullname='Capitulares',
    description=pt
        and 'Capitulares para EPUB com fontes ornamentais, pré-visualização, acentos e personalização por livro.'
        or 'Capitulares: EPUB drop caps with font preview, accented glyphs, and per-book customization.',
}
