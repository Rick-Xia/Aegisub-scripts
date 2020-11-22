
local tr = aegisub.gettext

script_version = "1.1"
script_name = tr"自动化边框添加".."v"..script_version
script_description = tr"为有配套边框的字幕样式批量添加边框"
script_author = tr"熨帖的浅井 https://space.bilibili.com/533070"

include("unicode.lua")
include("karaskel.lua")

local OK_BUTTON_TEXT = "OK"
local CANCEL_BUTTON_TEXT = "Cancel"
local DIALOGUE_TYPE_TEXT = "dialogue"

local AFFECTED_LINES_LABEL = "作用于哪些行  -------------------------------------------------------->>"
local AFFECTED_LINES_ALL_LABEL = "【全部】作用于全部行"
local AFFECTED_LINES_SELECTED_LABEL = "【自选】只作用于选中的行"

local NO_SPACE_REGEX = "^%s*(.-)%s*$"

-- The 2D table storing subtitle-frame combinations.
-- Structure be like:
-- {
--   "style name stem" -> { ..."full name of frames" }
-- }
local styleCombinationTable = {}
local dialog_config_base = {}

function initializeScriptState()
	styleCombinationTable = {}
	dialog_config_base =
	{
	    {class="label",x=0,y=0,label=""},
	    {class="label",x=0,y=1,label="------  简要说明  ------"},
	    {class="label",x=0,y=2,label="将边框样式取好与字幕主体相应的名字后，该脚本将自动为（全部或选中的）轴添加边框"},
	    {class="label",x=0,y=3,label="命名规则：{样式名}-{数字}。字幕主体的样式是最小的数字，各个边框从内到外数字依次增大"},
	    {class="label",x=0,y=4,label="例如："},
	    {class="label",x=0,y=5,label="  柴卡-1，柴卡-2，柴卡-3，柴卡-5，柴卡-10"},
	    {class="label",x=0,y=6,label="  这里的柴卡-1是字幕主体。 2，3，5，10是从内到外的四层边框"},
	    {class="label",x=0,y=7,label="※请使用半角英文短横- ※编号一定是正自然数 ※注意不要有全角空格"},
	    {class="label",x=0,y=8,label="使用前请保存。不过该脚本在运行前有存档点，发现不对的话可以Ctrl+Z退回"},
	    {class="label",x=0,y=9,label=""},
	}
end

-- Generate user input dialog using default fields and subtitle-frames.
function setDialogValues(styles)
	local yPos = #dialog_config_base
	function getY()
		yPos = yPos + 1
		return yPos - 1
	end

	table.insert(dialog_config_base, {class="label",x=0,y=getY(),label="------  检测到有边框的样式有  ------"})
	local startingLine = #dialog_config_base
	for key, _ in pairs(styleCombinationTable) do
		if #styleCombinationTable[key] > 1 then
			table.insert(dialog_config_base, {class="label",x=0,y=getY(),label="样式名\"" .. key .. "\"有  " .. #styleCombinationTable[key]-1 .. "  个边框样式"})
		end
	end

	if #dialog_config_base == startingLine then
		dialog_config_base[startingLine] = {class="label",x=0,y=getY(),label="没有检测到边框。请检查本体与边框样式名是否一致"}
	end

	table.insert(dialog_config_base, {class="label",x=0,y=getY(),label=""})
    table.insert(dialog_config_base, {class="label",x=0,y=getY(),width=1,height=1,label=AFFECTED_LINES_LABEL})
    table.insert(dialog_config_base, {class="dropdown",name=AFFECTED_LINES_LABEL,x=1,y=getY()-1,width=1,height=1,items={},value=""})
    table.insert(dialog_config_base, {class="label",x=0,y=getY()-1,label=""})

	lineSelectionOption = #dialog_config_base - 1
  	dialog_config_base[ lineSelectionOption ].items={}

  	table.insert(dialog_config_base[ lineSelectionOption ].items,AFFECTED_LINES_ALL_LABEL)
  	table.insert(dialog_config_base[ lineSelectionOption ].items,AFFECTED_LINES_SELECTED_LABEL)

  	dialog_config_base[ lineSelectionOption ].value = AFFECTED_LINES_SELECTED_LABEL
end

function getStyleNameStemWithoutSpace(styleName)
	local sIndex, eIndex = styleName:find("-")
	if sIndex == nil then
		return styleName
	else
		local front = styleName:sub(1, sIndex-1)
		return front:match(NO_SPACE_REGEX)
	end
end

function getStyleNameNumber(styleName)
	local sIndex, eIndex = styleName:find("-")
	local back = styleName:sub(eIndex+1)
	return tonumber(back:match(NO_SPACE_REGEX))
end

function styleNameCompare(left, right)
	local leftNumber = getStyleNameNumber(left)
	local rightNumber = getStyleNameNumber(right)
	if leftNumber == rightNumber then
		aegisub.log(1, "\n**检测到两个样式名字+序号重复。为防止产生未知后果，脚本中止\n")
		aegisub.log("  \"" .. left .. "\" 和 \"" .. right .. "\"\n")
		aegisub.cancel()
	end
	return leftNumber < rightNumber	
end

function sortFrames()
	for stem, frames in pairs(styleCombinationTable) do
		table.sort(styleCombinationTable[stem], styleNameCompare)
	end
end

function parseStyles(styles)
	for i=1,styles.n do
		local styleName = styles[i].name
		local sIndex, _ = styleName:find("-")
		if sIndex ~= nil then
			if getStyleNameNumber(styleName) ~= nil then
				local styleNameStem = getStyleNameStemWithoutSpace(styleName)
				local styleFrameCombination = styleCombinationTable[styleNameStem]
				if styleFrameCombination == nil then
					styleCombinationTable[styleNameStem] = { styleName }
				else
					table.insert(styleCombinationTable[styleNameStem], styleName)
				end
			end
		end
	end
end

function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
            end
            setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function layerSubtitles(subtitles, selected_lines)
	initializeScriptState()

	meta,styles = karaskel.collect_head(subtitles, false)
	parseStyles(styles)
	setDialogValues(styles)

	buttons, results = aegisub.dialog.display(dialog_config_base, { OK_BUTTON_TEXT, CANCEL_BUTTON_TEXT })
	if buttons ~= OK_BUTTON_TEXT then return end

	sortFrames()
	
	aegisub.log("开始添加边框:   ")
	local chosenLines = results[AFFECTED_LINES_LABEL];
	if chosenLines == AFFECTED_LINES_ALL_LABEL then
		aegisub.log("全部添加模式\n\n")
		aegisub.log("※添加了边框的行如下：\n")
		local i = 1
		while i <= subtitles.n do
			local base = subtitles[i]
			if base.class == DIALOGUE_TYPE_TEXT then
				local styleStem = getStyleNameStemWithoutSpace(base.style)
				local frames = styleCombinationTable[styleStem]

				if frames ~= nil and #frames > 1 and frames[1] == base.style then
					aegisub.log(base.raw:sub(11) .. "\n")
					local frameCount = #frames
					base.layer = frameCount - 1
					subtitles[i] = base

					for j=2, frameCount do
						local lineToInsert = deepcopy(base,nil)
						lineToInsert.style = frames[j]
						lineToInsert.layer = frameCount - j
						if i == subtitles.n then
							subtitles.append(lineToInsert)
						else
							subtitles.insert(i+1, lineToInsert)
						end
						i = i + 1
					end
				end
			end
			i = i + 1
		end
	end

	if chosenLines == AFFECTED_LINES_SELECTED_LABEL then
		aegisub.log("选中添加模式\n\n")
		aegisub.log("※添加了边框的行如下：\n")
		local addedLinesCount = 0
		for z, i in ipairs(selected_lines) do
			local actualPos = i + addedLinesCount
			local base = subtitles[actualPos]
			if base.class == DIALOGUE_TYPE_TEXT then
				local styleStem = getStyleNameStemWithoutSpace(base.style)
				local frames = styleCombinationTable[styleStem]

				if frames ~= nil and #frames > 1 and frames[1] == base.style then
					aegisub.log(base.raw:sub(11) .. "\n")
					local frameCount = #frames
					base.layer = frameCount - 1
					subtitles[actualPos] = base

					for j=2,frameCount do
						local lineToInsert = deepcopy(base,nil)
						lineToInsert.style = frames[j]
						lineToInsert.layer = frameCount - j
						if actualPos == subtitles.n then
							subtitles.append(lineToInsert)
						else
							subtitles.insert(actualPos+1, lineToInsert)
						end
						actualPos = actualPos + 1
						addedLinesCount = addedLinesCount + 1
					end
				end
			end
		end
	end
end

function script_main(subs,sel)
	layerSubtitles(subs, sel)
	aegisub.set_undo_point(script_name)
end

aegisub.register_macro(script_name, script_description, script_main)
