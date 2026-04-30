import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics

local SCREEN_W <const> = 400
local SCREEN_H <const> = 240
local BOOKS_DIR <const> = "books/"

local MARGIN_X <const> = 16
local MARGIN_TOP <const> = 12
local MARGIN_BOTTOM <const> = 24
local TEXT_W <const> = SCREEN_W - MARGIN_X * 2
local TEXT_H <const> = SCREEN_H - MARGIN_TOP - MARGIN_BOTTOM

local view = "library"
local books = {}
local selected = 1
local libraryScroll = 0

local currentBook = nil
local chapters = {}
local currentChapter = 1
local chapterSelected = 1
local chapterScroll = 0
local pages = {}
local currentPage = 1
local crankPageAccum = 0

-- File reading --------------------------------------------------------------

local function readFile(path)
    local f = playdate.file.open(path, playdate.file.kFileRead)
    if not f then return nil end
    local size = playdate.file.getSize(path)
    local content = f:read(size)
    f:close()
    return content
end

local function readJsonFile(path)
    local content = readFile(path)
    if not content then return nil end
    return json.decode(content)
end

-- Library -------------------------------------------------------------------

local function discoverBooks()
    local out = {}
    local entries = playdate.file.listFiles(BOOKS_DIR) or {}
    for _, name in ipairs(entries) do
        local lower = name:lower()
        if lower:sub(-4) == ".txt" then
            table.insert(out, { path = BOOKS_DIR .. name, title = name:sub(1, -5), format = "txt" })
        elseif lower:sub(-5) == ".json" then
            local data = readJsonFile(BOOKS_DIR .. name)
            if data then
                table.insert(out, {
                    path = BOOKS_DIR .. name,
                    title = data.title or name:sub(1, -6),
                    author = data.author,
                    format = "json",
                })
            end
        end
    end
    table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
    return out
end

-- Pagination ----------------------------------------------------------------

local function paginateText(text)
    local result = {}
    local paragraphs = {}
    for para in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(paragraphs, para)
    end

    local font = gfx.getFont()
    local lineHeight = font:getHeight() + font:getLeading()
    local pageLines = math.floor(TEXT_H / lineHeight)
    local pageTextH = pageLines * lineHeight

    local currentPageParas = {}
    local currentH = 0

    for _, para in ipairs(paragraphs) do
        if para == "" then
            local blankH = lineHeight
            if currentH + blankH > pageTextH and #currentPageParas > 0 then
                table.insert(result, table.concat(currentPageParas, "\n"))
                currentPageParas = {}
                currentH = 0
            end
            table.insert(currentPageParas, "")
            currentH = currentH + blankH
        else
            local _, paraH = gfx.getTextSizeForMaxWidth(para, TEXT_W)
            if currentH + paraH > pageTextH and #currentPageParas > 0 then
                table.insert(result, table.concat(currentPageParas, "\n"))
                currentPageParas = {}
                currentH = 0
            end

            if paraH <= pageTextH then
                table.insert(currentPageParas, para)
                currentH = currentH + paraH
            else
                -- Paragraph too tall for one page — split by words
                local words = {}
                for w in para:gmatch("%S+") do
                    table.insert(words, w)
                end
                local chunk = ""
                for _, word in ipairs(words) do
                    local test = chunk == "" and word or (chunk .. " " .. word)
                    local _, testH = gfx.getTextSizeForMaxWidth(test, TEXT_W)
                    if testH > pageTextH and chunk ~= "" then
                        if currentH > 0 and #currentPageParas > 0 then
                            table.insert(result, table.concat(currentPageParas, "\n"))
                            currentPageParas = {}
                            currentH = 0
                        end
                        table.insert(currentPageParas, chunk)
                        local _, chunkH = gfx.getTextSizeForMaxWidth(chunk, TEXT_W)
                        currentH = chunkH
                        if currentH >= pageTextH then
                            table.insert(result, table.concat(currentPageParas, "\n"))
                            currentPageParas = {}
                            currentH = 0
                        end
                        chunk = word
                    else
                        chunk = test
                    end
                end
                if chunk ~= "" then
                    if currentH > 0 and #currentPageParas > 0 then
                        local _, chunkH = gfx.getTextSizeForMaxWidth(chunk, TEXT_W)
                        if currentH + chunkH > pageTextH then
                            table.insert(result, table.concat(currentPageParas, "\n"))
                            currentPageParas = {}
                            currentH = 0
                        end
                    end
                    table.insert(currentPageParas, chunk)
                    local _, chunkH = gfx.getTextSizeForMaxWidth(chunk, TEXT_W)
                    currentH = currentH + chunkH
                end
            end
        end
    end

    if #currentPageParas > 0 then
        table.insert(result, table.concat(currentPageParas, "\n"))
    end

    if #result == 0 then
        table.insert(result, "")
    end

    return result
end

-- Open book -----------------------------------------------------------------

local function openChapter(chapterIdx)
    currentChapter = chapterIdx
    pages = paginateText(chapters[chapterIdx].text)
    currentPage = 1
    crankPageAccum = 0
    playdate.getCrankChange()
    view = "reading"
end

local function openBook(book)
    currentBook = book
    if book.format == "json" then
        local data = readJsonFile(book.path)
        if not data then return end
        chapters = {}
        if data.chapters and #data.chapters > 0 then
            for i, ch in ipairs(data.chapters) do
                local title = ch.title or ("Chapter " .. i)
                local text = ch.text or ""
                table.insert(chapters, { title = title, text = text })
            end
        else
            table.insert(chapters, { title = book.title, text = data.text or "" })
        end
        if #chapters == 1 then
            openChapter(1)
        else
            chapterSelected = 1
            chapterScroll = 0
            view = "chapters"
        end
    else
        local content = readFile(book.path)
        if not content then return end
        chapters = { { title = book.title, text = content } }
        openChapter(1)
    end
end

-- Drawing -------------------------------------------------------------------

local LIBRARY_ROW_H <const> = 24
local LIBRARY_VISIBLE_ROWS = math.floor((SCREEN_H - 48) / LIBRARY_ROW_H)

local function drawEmpty()
    gfx.clear()
    local dataPath = "/Data/com.ri604.reader/books/"
    gfx.drawTextAligned("Reader", SCREEN_W / 2, 24, kTextAlignment.center)
    gfx.drawTextAligned("No books found.", SCREEN_W / 2, 80, kTextAlignment.center)
    gfx.drawTextAligned("Copy .txt files into", SCREEN_W / 2, 120, kTextAlignment.center)
    gfx.drawTextAligned(dataPath, SCREEN_W / 2, 140, kTextAlignment.center)
    gfx.drawTextAligned("via Data Disk mode.", SCREEN_W / 2, 160, kTextAlignment.center)
end

local function drawScrollbar(count, sel, visibleRows, trackY, trackH)
    if count > visibleRows then
        local barH = 4
        local ratio = (sel - 1) / (count - 1)
        local dotY = trackY + ratio * (trackH - barH)
        gfx.fillRect(SCREEN_W - 6, dotY, 3, barH)
    end
end

local function drawLibrary()
    gfx.clear()
    gfx.drawTextAligned("Library", SCREEN_W / 2, 12, kTextAlignment.center)

    if selected < libraryScroll + 1 then
        libraryScroll = selected - 1
    elseif selected > libraryScroll + LIBRARY_VISIBLE_ROWS then
        libraryScroll = selected - LIBRARY_VISIBLE_ROWS
    end

    local y = 48
    for i = libraryScroll + 1, math.min(#books, libraryScroll + LIBRARY_VISIBLE_ROWS) do
        local prefix = (i == selected) and "> " or "  "
        local label = books[i].title
        if books[i].author then
            label = label .. " | " .. books[i].author
        end
        gfx.drawText(prefix .. label, 24, y)
        y = y + LIBRARY_ROW_H
    end

    drawScrollbar(#books, selected, LIBRARY_VISIBLE_ROWS, 48, LIBRARY_VISIBLE_ROWS * LIBRARY_ROW_H)
end

local function drawChapters()
    gfx.clear()
    local header = currentBook.title
    if currentBook.author then
        header = header .. " | " .. currentBook.author
    end
    gfx.drawTextAligned(header, SCREEN_W / 2, 12, kTextAlignment.center)

    if chapterSelected < chapterScroll + 1 then
        chapterScroll = chapterSelected - 1
    elseif chapterSelected > chapterScroll + LIBRARY_VISIBLE_ROWS then
        chapterScroll = chapterSelected - LIBRARY_VISIBLE_ROWS
    end

    local y = 48
    for i = chapterScroll + 1, math.min(#chapters, chapterScroll + LIBRARY_VISIBLE_ROWS) do
        local prefix = (i == chapterSelected) and "> " or "  "
        gfx.drawText(prefix .. chapters[i].title, 24, y)
        y = y + LIBRARY_ROW_H
    end

    drawScrollbar(#chapters, chapterSelected, LIBRARY_VISIBLE_ROWS, 48, LIBRARY_VISIBLE_ROWS * LIBRARY_ROW_H)
end

local function drawReading()
    gfx.clear()
    gfx.drawTextInRect(pages[currentPage], MARGIN_X, MARGIN_TOP, TEXT_W, TEXT_H)

    local footerLeft
    if #chapters > 1 then
        footerLeft = "Ch " .. currentChapter .. "/" .. #chapters .. "  " .. currentPage .. "/" .. #pages
    else
        footerLeft = currentPage .. " / " .. #pages
    end
    local percentStr = math.floor(currentPage / #pages * 100) .. "%"
    local footerY = SCREEN_H - MARGIN_BOTTOM + 6
    gfx.drawText(footerLeft, MARGIN_X, footerY)
    gfx.drawTextAligned(percentStr, SCREEN_W - MARGIN_X, footerY, kTextAlignment.right)

    local progressW = SCREEN_W - MARGIN_X * 2
    local progressY = SCREEN_H - MARGIN_BOTTOM + 2
    gfx.drawRect(MARGIN_X, progressY, progressW, 2)
    local fillW = math.floor(progressW * currentPage / #pages)
    gfx.fillRect(MARGIN_X, progressY, fillW, 2)
end

-- Update --------------------------------------------------------------------

function playdate.update()
    if view == "library" then
        if #books == 0 then
            drawEmpty()
        else
            drawLibrary()
        end
    elseif view == "chapters" then
        drawChapters()
    elseif view == "reading" then
        local change = playdate.getCrankChange()
        if math.abs(change) > 0 then
            crankPageAccum = crankPageAccum + change
            local threshold = 60
            if crankPageAccum >= threshold then
                crankPageAccum = 0
                if currentPage < #pages then
                    currentPage = currentPage + 1
                elseif currentChapter < #chapters then
                    openChapter(currentChapter + 1)
                end
            elseif crankPageAccum <= -threshold then
                crankPageAccum = 0
                if currentPage > 1 then
                    currentPage = currentPage - 1
                end
            end
        end
        drawReading()
    end
    playdate.timer.updateTimers()
end

-- Input ---------------------------------------------------------------------

function playdate.AButtonDown()
    if view == "library" and #books > 0 then
        openBook(books[selected])
    elseif view == "chapters" then
        openChapter(chapterSelected)
    end
end

function playdate.BButtonDown()
    if view == "reading" then
        if #chapters > 1 then
            view = "chapters"
        else
            view = "library"
        end
    elseif view == "chapters" then
        view = "library"
    end
end

function playdate.upButtonDown()
    if view == "library" and #books > 0 then
        selected = math.max(1, selected - 1)
    elseif view == "chapters" then
        chapterSelected = math.max(1, chapterSelected - 1)
    end
end

function playdate.downButtonDown()
    if view == "library" and #books > 0 then
        selected = math.min(#books, selected + 1)
    elseif view == "chapters" then
        chapterSelected = math.min(#chapters, chapterSelected + 1)
    end
end

function playdate.leftButtonDown()
    if view == "reading" then
        if currentPage > 1 then
            currentPage = currentPage - 1
            crankPageAccum = 0
        elseif currentChapter > 1 then
            openChapter(currentChapter - 1)
            currentPage = #pages
        end
    end
end

function playdate.rightButtonDown()
    if view == "reading" then
        if currentPage < #pages then
            currentPage = currentPage + 1
            crankPageAccum = 0
        elseif currentChapter < #chapters then
            openChapter(currentChapter + 1)
        end
    end
end

-- Init ----------------------------------------------------------------------

gfx.setFont(gfx.getSystemFont(gfx.font.kVariantBold))
books = discoverBooks()
