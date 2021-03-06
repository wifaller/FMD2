function Init()
	local function AddWebsiteModule(id, name, url)
		local m = NewWebsiteModule()
		m.ID                         = id
		m.Name                       = name
		m.RootURL                    = url
		m.Category                   = 'English'
		m.OnGetDirectoryPageNumber   = 'GetDirectoryPageNumber'
		m.OnGetNameAndLink           = 'GetNameAndLink'
		m.OnGetInfo                  = 'GetInfo'
		m.OnGetPageNumber            = 'GetPageNumber'
		m.SortedList                 = true
	end
	AddWebsiteModule('4f40515fb43640ddb08eb61278fc97a5', 'KissManga', 'https://kissmanga.com')
	AddWebsiteModule('1a7b98800a114a3da5f48de91f45a880', 'ReadComicOnline', 'https://readcomiconline.to')
end

function GetDirectoryPageNumber()
	local url = MODULE.RootURL
	if MODULE.ID == '4f40515fb43640ddb08eb61278fc97a5' then
		url = url .. '/MangaList/Newest'
	elseif MODULE.ID == '1a7b98800a114a3da5f48de91f45a880' then
		url = url .. '/ComicList/Newest'
	end
	if HTTP.GET(url) then
		PAGENUMBER = tonumber(CreateTXQuery(HTTP.Document).x.XPathString('//ul[@class="pager"]/li[last()]/a/@href'):match('=(%d+)$')) or 1
		return no_error
	else
		return net_problem
	end
end

function GetNameAndLink()
	local url = MODULE.RootURL
	if MODULE.ID == '4f40515fb43640ddb08eb61278fc97a5' then
		url = url .. '/MangaList/Newest'
	elseif MODULE.ID == '1a7b98800a114a3da5f48de91f45a880' then
		url = url .. '/ComicList/Newest'
	end
	if URL ~= '0' then
		url = url .. '?page=' .. (URL + 1)
	end
	if HTTP.GET(url) then
		CreateTXQuery(HTTP.Document).XPathHREFAll('//table[@class="listing"]/tbody/tr/td[1]/a', LINKS, NAMES)
		return no_error
	else
		return net_problem
	end
end

function GetInfo()
	MANGAINFO.URL=MaybeFillHost(MODULE.RootURL,URL)
	if HTTP.GET(MANGAINFO.URL) then
		local x = CreateTXQuery(HTTP.Document)
		MANGAINFO.Title     = x.XPathString('//title'):match('^[\r\n%s]-(.-)[\r\n]')
		MANGAINFO.CoverLink = MaybeFillHost(MODULE.RootURL, x.XPathString('//div[@id="rightside"]//img/@src'))
		MANGAINFO.Authors   = x.XPathStringAll('//div[@class="barContent"]//span[starts-with(., "Author") or starts-with(., "Writer")]/parent::*/a')
		MANGAINFO.Artists   = x.XPathStringAll('//div[@class="barContent"]//span[starts-with(., "Artist")]/parent::*/a')
		MANGAINFO.Summary   = x.XPathString('//div[@class="barContent"]/div/p[starts-with(.,"Summary:")]//following-sibling::p[1]')
		MANGAINFO.Genres    = x.XPathStringAll('//div[@class="barContent"]//span[starts-with(., "Genre")]/parent::*/a')
		MANGAINFO.Status    = MangaInfoStatusIfPos((x.XPathString('//div[@class="barContent"]/div/p[starts-with(.,"Status:")]')))

		local namePattern = '^Read (.+) online$'
		if MODULE.ID == '1a7b98800a114a3da5f48de91f45a880' then namePattern = '^Read (.+) comic online' end
		local v, name; for v in x.XPath('//table[@class="listing"]/tbody/tr/td/a').Get() do
			MANGAINFO.ChapterLinks.Add(v.GetAttribute('href'))
			name = v.GetAttribute('title'):match(namePattern)
			MANGAINFO.ChapterNames.Add(name)
		end
		MANGAINFO.ChapterLinks.Reverse(); MANGAINFO.ChapterNames.Reverse()
		return no_error
	else
		return net_problem
	end
end

function GetPageNumber()
	HTTP.Cookies.Values['rco_quality'] = 'hq'
	if HTTP.GET(MaybeFillHost(MODULE.RootURL, URL)) then
		local body = HTTP.Document.ToString()
		local s = body:match('var%s+lstImages%s+.-;(.-)%s+var%s')
		local i; for i in s:gmatch('%("(.-)"%)') do
			TASK.PageLinks.Add(i)
		end

		if TASK.PageLinks.Count == 0 then return false end
		-- kissmanga encrypted data
		if (MODULE.ID == '4f40515fb43640ddb08eb61278fc97a5') and HTTP.GET(MODULE.RootURL .. '/Scripts/lo.js') then
			local LOGGER = require 'fmd.logger'
			local crypto = require 'fmd.crypto'
			local key, iv
			-- get the key and initialization vector

			local function JSHexToStr(str)
				return str:gsub('\\x',''):gsub('%x%x',function(c)return c.char(tonumber(c,16))end)
			end

			local chko2 = body:match('%["([^"]+)"%]; chko = _?') or ''
			local chko2_plus = body:match('chko = .+%["([^"]+)"%]; chko = ') or ''
			chko2 = JSHexToStr(chko2)
			chko2_plus = JSHexToStr(chko2_plus)

			local bodyjs = HTTP.Document.ToString()
			local iv_p = tonumber(bodyjs:match('boxzq=.-%[(%d+)%]')) or nil
			local chko_s, chko_p = bodyjs:match('chko=(.-)%[(%d+)%]'); chko_p = tonumber(chko_p) or nil

			if (chko_s ~= nil) and (chko_p ~= nil) then
				local s = bodyjs:match(chko_s .. '=%[(.-)%]')
				local t = {}
				for i in s:gmatch('"(.-)"') do
					table.insert(t, i)
				end
				chko1 = JSHexToStr(t[chko_p+1])
				iv = JSHexToStr(t[iv_p+1])

				local test_p = TASK.PageLinks[0]
				local function testkeyiv(akey)
					if crypto.AESDecryptCBCSHA256Base64Pkcs7(test_p, akey, iv):find('://') then
						key = akey
						return true
					else
						return false
					end
				end

				-- test all possibilities
				if not testkeyiv(chko2 .. chko2_plus) then
				if not testkeyiv(chko2_plus) then
				if not testkeyiv(chko2) then
				if not testkeyiv(chko1) then
				if not testkeyiv(chko1 .. chko2) then
				if not testkeyiv(chko2 .. chko1) then
				end end end end end end

				if (key ~= nil) then
					for i=0,TASK.PageLinks.Count-1 do
						TASK.PageLinks[i] = crypto.AESDecryptCBCSHA256Base64Pkcs7(TASK.PageLinks[i], key, iv)
					end
				else
					LOGGER.SendError(string.format([[KissManga: failed to get a key to decrypt
iv          : %s
chko1       : %s
chko2       : %s
chko2_plus  : %s
test_string : %s
					]], tostring(iv), tostring(chko1), tostring(chko2), tostring(chko2_plus), test_p))
					TASK.PageLinks.Clear()
					return false
				end
			else
				LOGGER.SendError('[KissManga] unable to extract the parameters to decrypt ' .. URL)
				return false
			end
		end
		return true
	else
		return false
	end
end
