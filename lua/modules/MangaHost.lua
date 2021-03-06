----------------------------------------------------------------------------------------------------
-- Local Constants
----------------------------------------------------------------------------------------------------

local DirectoryPagination = '/mangas/page/'

----------------------------------------------------------------------------------------------------
-- Event Functions
----------------------------------------------------------------------------------------------------

-- Get info and chapter list for current manga.
function GetInfo()
	local t, v, x = nil
	local u = MaybeFillHost(MODULE.RootURL, URL)

	if not HTTP.GET(u) then return net_problem end

	x = CreateTXQuery(HTTP.Document)
	MANGAINFO.Title     = x.XPathString('//meta[@property="og:title"]/@content')
	MANGAINFO.CoverLink = x.XPathString('//img[contains(@class, "thumbnail")]/@src')
	MANGAINFO.Status    = MangaInfoStatusIfPos(x.XPathString('//li[contains(strong, "Status:")]/text()'), 'Ativo', 'Completo')
	MANGAINFO.Authors   = x.XPathString('//li[contains(strong, "Autor:")]/text()')
	MANGAINFO.Artists   = x.XPathString('//li[contains(strong, "Desenho (Art):")]/text()')
	MANGAINFO.Genres    = x.XPathStringAll('//li[contains(strong, "Categoria(s):")]/a')
	MANGAINFO.Summary   = Trim(x.XPathString('//div[@id="divSpdInText"]/p[1]'))

	if x.XPathCount('//ul[@class="list_chapters"]') > 0 then
		v = x.XPath('//ul[@class="list_chapters"]//a')
		for i = 1, v.Count do
			t = TXQuery.New()
			t.ParseHTML(v.Get(i).GetAttribute('data-content'))
			MANGAINFO.ChapterLinks.Add(t.XPathString('//a/@href'))
			MANGAINFO.ChapterNames.Add(v.Get(i).GetAttribute('title'))
		end
	else
		x.XPathHREFAll('//a[@class="capitulo"]', MANGAINFO.ChapterLinks, MANGAINFO.ChapterNames)
	end
	MANGAINFO.ChapterLinks.Reverse(); MANGAINFO.ChapterNames.Reverse()

	return no_error
end

-- Get the page count of the manga list of the current website.
function GetDirectoryPageNumber()
	local u = MODULE.RootURL .. DirectoryPagination .. 1

	if not HTTP.GET(u) then return net_problem end

	PAGENUMBER = tonumber(CreateTXQuery(HTTP.Document).XPathString('(//div[@class="wp-pagenavi"])[1]//a[@class="last"]/@href'):match('.-/page/(%d+)'))

	return no_error
end

-- Get LINKS and NAMES from the manga list of the current website.
function GetNameAndLink()
	local x = nil
	local u = MODULE.RootURL .. DirectoryPagination .. (URL + 1)

	if not HTTP.GET(u) then return net_problem end

	x = CreateTXQuery(HTTP.Document)
	x.XPathHREFAll('//div[@class="list clearfix"]//h3/a', LINKS, NAMES)

	return no_error
end

-- Get the page count for the current chapter.
function GetPageNumber()
	local x = nil
	local u = MaybeFillHost(MODULE.RootURL, URL)

	if not HTTP.GET(u) then return net_problem end

	x = CreateTXQuery(HTTP.Document)
	x.ParseHTML(GetBetween('var images = ["', '"];', x.XPathString('//script[contains(., "var images = ")]')):gsub('"', ''):gsub('\'', '"'))
	x.XPathStringAll('//img/@src', TASK.PageLinks)

	return no_error
end

----------------------------------------------------------------------------------------------------
-- Module Initialization
----------------------------------------------------------------------------------------------------

function Init()
	local m = NewWebsiteModule()
	m.ID                       = '47a611b9efb44e34a800bdb0f946ff07'
	m.Name                     = 'MangaHost'
	m.RootURL                  = 'https://mangahosted.com'
	m.Category                 = 'Portuguese'
	m.OnGetInfo                = 'GetInfo'
	m.OnGetDirectoryPageNumber = 'GetDirectoryPageNumber'
	m.OnGetNameAndLink         = 'GetNameAndLink'
	m.OnGetPageNumber          = 'GetPageNumber'
end