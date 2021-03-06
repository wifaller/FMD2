----------------------------------------------------------------------------------------------------
-- Module Initialization
----------------------------------------------------------------------------------------------------

local _M = {}

----------------------------------------------------------------------------------------------------
-- Local Constants
----------------------------------------------------------------------------------------------------

DirectoryPagination = '/browse?sort=title&page='

----------------------------------------------------------------------------------------------------
-- Event Functions
----------------------------------------------------------------------------------------------------

-- Get info and chapter list for current manga.
function _M.GetInfo()
  local lang, x = nil
  local u = MaybeFillHost(MODULE.RootURL, URL)

  if not HTTP.GET(u) then return net_problem end

  x = CreateTXQuery(HTTP.Document)
  MANGAINFO.Title     = x.XPathString('//h3[@class="item-title"]/a') .. _M.GetLanguageCodeSuffix(x.XPathString('//h3[@class="item-title"]/parent::*/span[contains(@class, "flag")]/@class'))
  MANGAINFO.CoverLink = x.XPathString('//div[contains(@class, "attr-cover")]/img/@src')
  MANGAINFO.Authors   = x.XPathStringAll('//div[@class="attr-item" and contains(b, "Authors")]/span')
  MANGAINFO.Genres    = _M.GetGenres(x.XPathString('//div[@class="attr-item" and contains(b, "Genres")]/span'))
  MANGAINFO.Status    = MangaInfoStatusIfPos(x.XPathString('//div[@class="attr-item" and contains(b, "Status")]/span'))
  MANGAINFO.Summary   = x.XPathString('//h5/following-sibling::pre')

  x.XPathHREFAll('//div[contains(@class, "chapter-list")]/div[@class="main"]/div/a', MANGAINFO.ChapterLinks, MANGAINFO.ChapterNames)
  MANGAINFO.ChapterLinks.Reverse(); MANGAINFO.ChapterNames.Reverse()

  return no_error
end

-- Get the page count of the manga list of the current website.
function _M.GetDirectoryPageNumber()
  local u = MODULE.RootURL .. DirectoryPagination .. 1

  if not HTTP.GET(u) then return net_problem end

  PAGENUMBER = tonumber(CreateTXQuery(HTTP.Document).XPathString('(//ul[contains(@class, "pagination")])[1]/li[last()-1]')) or 1

  return no_error
end

-- Get LINKS and NAMES from the manga list of the current website.
function _M.GetNameAndLink()
  local u = MODULE.RootURL .. DirectoryPagination .. (URL + 1)

  if not HTTP.GET(u) then return net_problem end

  local x, v
  x = CreateTXQuery(HTTP.Document)
  for v in x.XPath('//div[@id="series-list"]/div/div').Get() do
    LINKS.Add(x.XPathString('a/@href', v))
    NAMES.Add(x.XPathString('a', v) .. _M.GetLanguageCodeSuffix(x.XPathString('span[contains(@class, "flag")]/@class', v)))
  end

  return no_error
end

-- Get the page count for the current chapter.
function _M.GetPageNumber()
  local s, x = nil
  local u = MaybeFillHost(MODULE.RootURL, URL)

  if not HTTP.GET(u) then return net_problem end

  x = CreateTXQuery(HTTP.Document)
  x.ParseHTML(GetBetween('var images = ', ';', x.XPathString('//script[contains(., "var images = ")]')))
  x.XPathStringAll('let $c := json(*) return for $k in jn:keys($c) return $c($k)', TASK.PageLinks)

  return no_error
end

----------------------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------------------

-- Get the language suffix by given flag.
function _M.GetLanguageCodeSuffix(s)
  local suffix = ' [EN]'

  if s and (s ~= '') then
    s = s:match('flag_(%S+)')
    if s and (s ~= 'united_kingdom') then suffix = ' [' .. string.upper(s) .. ']' end
  end

  return suffix
end

-- Get the genre list as string.
function _M.GetGenres(s)
  local genres = ''

  for i in string.gmatch(s, '([^/]+)') do
    if genres == '' then genres = genres .. (Trim(i)) else genres = genres .. ', ' .. (Trim(i)) end
  end

  return genres
end

----------------------------------------------------------------------------------------------------
-- Module After-Initialization
----------------------------------------------------------------------------------------------------

return _M