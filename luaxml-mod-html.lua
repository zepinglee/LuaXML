-- HTML parser
-- inspired by https://browser.engineering/html.html
-- but then redone using https://html.spec.whatwg.org/multipage/parsing.html
local M = {}

-- use local copies of utf8 functions
local ucodepoint = utf8.codepoint
local utfchar      = utf8.char
local function uchar(codepoint)
  if codepoint and codepoint > -1 then
    return utfchar(codepoint)
  end
  return ""
end

-- we must make search tree for named entities, as their support 
-- is quite messy
local named_entities = require "luaxml-namedentities"

local entity_tree = {children = {}}

local function update_tree(tree, char)
  local children = tree.children or {}
  local current = children[char] or {}
  children[char] = current
  tree.children = children
  return current
end

-- loop over named entities and update tree
for entity, char in pairs(named_entities) do
  local tree = entity_tree
  for char in entity:gmatch(".") do
    tree = update_tree(tree,char)
  end
  tree.entity = entity
  tree.char   = char
end

local function search_entity_tree(tbl) 
  -- get named entity for the list of characters
  local tree = entity_tree
  for _,char in ipairs(tbl) do 
    if tree.children then
      tree = tree.children[char]
      if not tree then return nil end
    else
      return nil
    end
  end
  -- print("tree", tree.char)
  return tree
end


-- declare  basic node types

local Root = {
  _type = "root"
}

function Root:init()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.__tostring = function (x) return "_ROOT" end
  o.children = {}
  return o
end

function Root:add_child(node)
  table.insert(self.children, node)
end

local Doctype = {
  _type = "doctype"
}
function Doctype:init(name, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.__tostring = function (x) 
    if x.data then
      return "<!DOCTYPE " .. x.name .. " " .. x.data ..  ">" 
    else
      return "<!DOCTYPE " .. x.name .. ">" 
    end
  end
  self.add_child = Root.add_child
  o.parent = parent
  o.name = name
  o.children = {}
  return o
end

function Doctype:add_data(data)
  self.data = data
end


local Text = {
  _type = "text"
}

function Text:init(text, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.text = text
  self.__tostring = function (x) return "'" ..  x.text .. "'" end
  self.add_child = Root.add_child
  o.parent = parent
  o.children = {}
  return o
end

local Comment = {
  _type = "comment"
}

function Comment:init(text, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.text = text
  self.__tostring = function (x) return "<!--" ..  x.text .. "-->" end
  self.add_child = Root.add_child
  o.parent = parent
  o.children = {}
  return o
end



local Element = {
  _type = "element"
}

function Element:init(tag, parent)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  -- tag can be table with unicode characters
  if type(tag) == "table" then
    o.tag = table.concat(tag)
  else
    o.tag = tag
  end
  self.__tostring = function(x) 
    local attr = {}
    for _, el in ipairs(x.attr) do 
      -- handle attributes
      local value
      if el.value:match('"') then
        value = "'" .. el.value .. "'"
      else
        value = '"' .. el.value .. '"'
      end
      attr[#attr+1] =  el.name .. "=" .. value
    end
    local closing = ">"
    if x.self_closing then
      closing = " />"
    end
    if #attr > 0 then
      return "<" .. x.tag .. " " .. table.concat(attr, " ") .. closing 
    else
      return "<" .. x.tag .. closing
    end
  end
  self.add_child = Root.add_child
  o.children = {}
  o.attr     = {}
  o.parent = parent
  return o
end

-- state machine functions

-- each function takes HtmlParser as an argument
local HtmlStates = {}

-- declare codepoints for more efficient processing
local less_than      = ucodepoint("<")
local greater_than   = ucodepoint(">")
local amperesand     = ucodepoint("&")
local exclam         = ucodepoint("!")
local question       = ucodepoint("?")
local solidus        = ucodepoint("/")
local equals         = ucodepoint("=")
local quoting        = ucodepoint('"')
local apostrophe     = ucodepoint("'")
local semicolon      = ucodepoint(";")
local hyphen         = ucodepoint("-")
local numbersign     = ucodepoint("#")
local smallx         = ucodepoint("x")
local bigx           = ucodepoint("X")
local EOF            = -1 -- special character, meaning end of stream
local null           = 0

local function is_upper_alpha(codepoint)
  if (64 < codepoint and codepoint < 91) then
    return true
  end
end
local function is_lower_alpha(codepoint)
  if (96 < codepoint and codepoint < 123) then 
    return true
  end
end

local function is_alpha(codepoint)
  -- detect if codepoint is alphanumeric
  if is_upper_alpha(codepoint) or
     is_lower_alpha(codepoint) then
       return true
  end
  return false
end


local function is_numeric(codepoint)
  if 47 < codepoint and codepoint < 58 then
    return true
  end
end

local function is_upper_hex(codepoint)
  if 64 < codepoint and codepoint < 71 then
    return true
  end
end

local function is_lower_hex(codepoint)
  if 96 < codepoint and codepoint < 103 then
    return true
  end
end

local function is_hexadecimal(codepoint) 
  if is_numeric(codepoint) or
     is_lower_hex(codepoint) or
     is_upper_hex(codepoint)
  then 
    return true
  end
end


local function is_alphanumeric(codepoint)
  return is_alpha(codepoint) or is_numeric(codepoint)
end

local function is_space(codepoint) 
  -- detect space characters
  if codepoint==0x0009 or codepoint==0x000A or codepoint==0x000C or codepoint==0x0020 then
    return true
  end
  return false
end

local function is_surrogate(codepoint)
  return  0xD800 <= codepoint and codepoint <= 0xDFFF
end


character_entity_replace_table = {
[0x80] =  0x20AC,  
[0x82] =  0x201A,  
[0x83] =  0x0192,  
[0x84] =  0x201E,  
[0x85] =  0x2026,  
[0x86] =  0x2020,  
[0x87] =  0x2021,  
[0x88] =  0x02C6,  
[0x89] =  0x2030,  
[0x8A] =  0x0160,  
[0x8B] =  0x2039,  
[0x8C] =  0x0152,  
[0x8E] =  0x017D,  
[0x91] =  0x2018,  
[0x92] =  0x2019,  
[0x93] =  0x201C,  
[0x94] =  0x201D,  
[0x95] =  0x2022,  
[0x96] =  0x2013,  
[0x97] =  0x2014,  
[0x98] =  0x02DC,  
[0x99] =  0x2122,  
[0x9A] =  0x0161,  
[0x9B] =  0x203A,  
[0x9C] =  0x0153,  
[0x9E] =  0x017E,  
[0x9F] =  0x0178  
}

HtmlStates.data = function(parser) 
  -- this is the default state
  local codepoint = parser.codepoint
  -- print("codepoint", parser.codepoint)
  if codepoint == less_than then
    -- start of tag
    return "tag_open"
  elseif codepoint  == amperesand then
    -- we must save the current state 
    -- what we will return to after entity
    parser.return_state = "data"
    return "character_reference" 
  elseif codepoint == EOF then
    parser:start_token("end_of_file", {})
    parser:emit()
  else
    parser:emit_character(uchar(codepoint))
  end
  return "data"
end

HtmlStates.tag_open = function(parser)
  -- parse tag contents
  local codepoint = parser.codepoint
  if codepoint == exclam then
    return "markup_declaration_open"
  elseif codepoint == solidus then
    return "end_tag_open"
  elseif codepoint == question then
    parser:start_token("comment",{data={}})
    return "bogus_comment"
  elseif is_alpha(codepoint) then
    local data = {
      name = {},
      attr = {},
      current_attr_name = {},
      current_attr_value = {},
      self_closing = false
    }
    parser:start_token("start_tag", data)
    return parser:tokenize("tag_name")
  elseif codepoint == EOF then
    parser:emit_character(">")
    parser:start_token("end_of_file", {})
    parser:emit()
  else
    -- invalid tag
    -- emit "<" and reconsume current character as data
    parser:emit_character("<")
    return parser:tokenize("data")
  end
end

HtmlStates.character_reference = function(parser)
  -- parse HTML entities
  -- initialize temp buffer
  parser.temp_buffer = {"&"}
  local codepoint = parser.codepoint
  if is_alphanumeric(codepoint) then
    return parser:tokenize("named_character_reference")
  elseif codepoint == numbersign then
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "numeric_character_reference"
  else
    parser:flush_temp_buffer()
    return parser:tokenize(parser.return_state)
  end

end

HtmlStates.named_character_reference = function(parser)
  -- named entity parsing is pretty complicated 
  -- https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
  local codepoint = parser.codepoint
  -- test if the current entity name is included in the named entity list
  local search_table = {}
  -- first char in temp buffer is &, which we don't want to lookup in the search tree
  for i=2, #parser.temp_buffer do search_table[#search_table+1] = parser.temp_buffer[i] end
  if codepoint == semicolon then
    -- close named entity
    local entity = search_entity_tree(search_table) 
    if entity and entity.char then
      parser:add_entity(entity.char)
    else
      -- if the current name doesn't correspond to any named entity, flush everything into text
      parser:flush_temp_buffer()
      return parser:tokenize(parser.return_state)
    end
    return parser.return_state
  else
    local char = uchar(codepoint)
    -- try if the current entity name is in the named entity search tree
    table.insert(search_table, char)
    local entity = search_entity_tree(search_table)
    if entity then
      -- keep parsing name entity while we match a name
      table.insert(parser.temp_buffer, char)
      return "named_character_reference"
    else
      -- here this will be more complicated
      if #search_table > 1 then
        local token = parser.current_token
        if token.type == "start_tag" and (codepoint == equals or is_alphanumeric(codepoint)) then
          -- in attribute value, flush characters and retokenize  
          parser:flush_temp_buffer()
          return parser:tokenize(parser.return_state)
        else
          -- try to get entity for characters preceding the current character
          table.remove(search_table)
          local newentity = search_entity_tree(search_table)
          if newentity and newentity.char then
            parser:add_entity(newentity.char)
          else
            -- we need to find if parts of the current substring match a named entity
            -- for example &notit; -> ¬it; but &notin; -> ∉
            local rest = {}
            -- loop over the table with characters, and try to find if it matches entity
            for i = #search_table, 1,-1 do
              local removed_char = table.remove(search_table)
              -- 
              table.insert(rest, 1, removed_char)
              newentity = search_entity_tree(search_table)
              if newentity and newentity.char then
                parser:add_entity(newentity.char)
                parser.temp_buffer = rest
                break
              end
            end
            -- replace temporary buffer witch characters that followed the matched entity
            parser:flush_temp_buffer()
          end
          return parser:tokenize(parser.return_state)
        end
      else
        -- search table contains only the current character
        parser:flush_temp_buffer()
        return parser:tokenize(parser.return_state)
      end
    end
  end

end

HtmlStates.numeric_character_reference = function(parser)
  -- this variable will hold the number
  local codepoint = parser.codepoint
  parser.character_reference_code = 0
  if codepoint == smallx or codepoint == bigx then
    -- hexadecimal entity
    table.insert(parser.temp_buffer, uchar(codepoint))
    return "hexadecimal_character_reference_start"
  else
    -- try decimal entity
    return parser:tokenize("decimal_character_reference_start")
  end

end

HtmlStates.hexadecimal_character_reference_start = function(parser)
  local codepoint = parser.codepoint
  if is_hexadecimal(codepoint) then
    return parser:tokenize("hexadecimal_character_reference")
  else
    parser:flush_temp_buffer()
    return parser:tokenize(parser.return_state)
  end
end

HtmlStates.decimal_character_reference_start = function(parser)
  local codepoint = parser.codepoint
  if is_numeric(codepoint) then
    return parser:tokenize("decimal_character_reference")
  else
    parser:flush_temp_buffer()
    return parser:tokenize(parser.return_state)
  end
end


HtmlStates.decimal_character_reference = function(parser)
  local codepoint = parser.codepoint
  -- helper functions for easier working with the character_reference_code
  local function multiply(number)
    parser.character_reference_code = parser.character_reference_code * number
  end
  local function add(number)
    parser.character_reference_code = parser.character_reference_code + number
  end
  if is_numeric(codepoint) then
    multiply(10)
    add(codepoint - 0x30)
  elseif codepoint == semicolon then
    return "numeric_reference_end_state"
  else
    -- this adds current entity
    parser:tokenize("numeric_reference_end_state")
    -- now tokenize the current character
    return parser:tokenize(parser.return_state)
  end
  return "decimal_character_reference"
end

HtmlStates.hexadecimal_character_reference = function(parser)
  local codepoint = parser.codepoint
  -- helper functions for easier working with the character_reference_code
  local function multiply(number)
    parser.character_reference_code = parser.character_reference_code * number
  end
  local function add(number)
    parser.character_reference_code = parser.character_reference_code + number
  end
  if is_numeric(codepoint) then
    multiply(16)
    add(codepoint - 0x30)
  elseif is_upper_hex(codepoint) then
    multiply(16)
    add(codepoint - 0x37)
  elseif is_lower_hex(codepoint) then
    multiply(16)
    add(codepoint - 0x57)
  elseif codepoint == semicolon then
    return "numeric_reference_end_state"
  else
    -- this adds current entity
    parser:tokenize("numeric_reference_end_state")
    -- now tokenize the current character
    return parser:tokenize(parser.return_state)
  end
  return "hexadecimal_character_reference"
end

HtmlStates.numeric_reference_end_state = function(parser)
  -- in this state, we don't need to 
  local character = parser.character_reference_code
  -- we need to clean invalid character codes
  if character == 0x00 or 
     character >  0x10FFFF or
     is_surrogate(character) 
  then
    character = 0xFFFD
  -- should we add special support for "noncharacter"? I think we can pass them to the output anyway
  elseif character_entity_replace_table[character] then 
    character = character_entity_replace_table[character]
  end
  parser:add_entity(uchar(character))
  return parser.return_state
end


HtmlStates.markup_declaration_open = function(parser)
  -- started by <!
  -- we now need to find the following text, to find if we started comment, doctype, or cdata
  local comment_pattern = "^%-%-"
  local doctype_pattern = "^[Dd][Oo][Cc][Tt][Yy][Pp][Ee]"
  local cdata_pattern   = "^%[CDATA%["
  local start_pos = parser.position
  local text = parser.body
  if text:match(comment_pattern, start_pos) then
    -- local _, newpos = text:find(comment_pattern, start_pos)
    -- we need to ignore next few characters
    parser.ignored_pos = start_pos + 1
    parser:start_token("comment", {data = {}})
    return "comment_start"
  elseif text:match(doctype_pattern, start_pos) then
    parser.ignored_pos = start_pos + 6
    parser:start_token("doctype", {name = {}, data = {}, force_quirks = false})
    return "doctype"
  elseif text:match(cdata_pattern, start_pos) then
    parser.ignored_pos = start_pos + 6
    -- we change CDATA simply to comments
    parser:start_token("comment", {data = {"[CDATA["}})
    return "bogus_comment"
  else
    parser:start_token("comment", {data = {}})
    return "bogus_comment"
  end
  -- local start, stop = string.find(parser.body, comment_pattern, parser.position)
end


HtmlStates.comment_start = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_start_dash"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_start_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_end"
  elseif codepoint == greater_than then
    parser:emit()
    return data
  elseif codepoint == EOF then
    parser:emit()
    parser:start_token("end_of_file", {})
    parser:emit()
  else
    parser:append_token_data("data", "-")
    return parser:tokenize("comment")
  end
end

HtmlStates.comment = function(parser)
  local codepoint = parser.codepoint
  if codepoint == less_than then
    parser:append_token_data("data", uchar(codepoint))
    return "comment_less_than"
  elseif codepoint == hyphen then
    return "comment_end_dash"
  elseif codepoint == null then
    parser:append_token_data("data", uchar(0xFFFD))
  elseif codepoint == EOF then
    parser:emit()
    parser:start_token("end_of_file", {})
    parser:emit()
  else
    parser:append_token_data("data", uchar(codepoint))
  end
  return "comment"
end

HtmlStates.comment_less_than = function(parser)
  local codepoint = parser.codepoint
  if codepoint == exclam then
    parser:append_token_data("data", uchar(codepoint))
    return "comment_less_than_bang"
  elseif codepoint == less_than then
    parser:append_token_data("data", uchar(codepoint))
    return "comment_less_than"
  else
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_less_than_bang = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_less_than_bang_dash"
  else
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_less_than_bang_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_less_than_bang_dash_dash"
  else
    return parser:tokenize("comment_end_dash")
  end

end

HtmlStates.comment_less_than_bang_dash_dash = function(parser)
  -- these comment states start to be ridiculous
  local codepoint = parser.codepoint
  if codepoint == greater_than or codepoint == EOF then
    return parser:tokenize("comment_end")
  else
    return parser:tokenize("comment_end")
  end
end

HtmlStates.comment_end_dash = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    return "comment_end"
  elseif codepoint == EOF then
    parser:emit()
    parser:start_token("end_of_file", {})
    parser:emit()
  else
    parser:append_token_data("data", uchar(codepoint))
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_end = function(parser)
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == exclam then
    return "comment_end_bang"
  elseif codepoint == hyphen then
    parser:append_token_data("data", "-")
    return "comment_end"
  elseif codepoint == EOF then
    parser:emit()
    parser:start_token("end_of_file")
    parser:emit()
  else
    parser:append_token_data("data", "--")
    return parser:tokenize("comment")
  end
end

HtmlStates.comment_end_bang = function(parser)
  local codepoint = parser.codepoint
  if codepoint == hyphen then
    parser:append_token_data("data", "--!")
    return "comment_end_dash"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    parser:emit()
    parser:start_token("end_of_file")
    parser:emit()
  else
    parser:append_token_data("data", "--!")
    return parser:tokenize("comment")
  end
end

HtmlStates.end_tag_open = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    local data = {
      name = {}
    }
    parser:start_token("end_tag", data)
    return parser:tokenize("tag_name")
  elseif codepoint == greater_than then
    return "data"
  else
    data = {
      data = {}
    }
    parser:start_token("comment", data)
    return parser:tokenize("bogus_comment")
  end
end

HtmlStates.bogus_comment = function(parser)
  -- started by <?
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    parser:emit()
    parser:start_token("end_of_file", {})
    parser:emit()
  elseif codepoint == null then
    parser:append_token_data("data", uchar(0xFFFD))
  else
    parser:append_token_data("data", uchar(codepoint))
    return "bogus_comment"
  end
end

local function doctype_eof(parser)
    parser:set_token_data("force_quirks", true)
    parser:emit()
    parser:start_token("end_of_file")
    parser:emit()
end

HtmlStates.doctype = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_doctype_name"
  elseif codepoint == greater_than then
    return parser:tokenize("before_doctype_name")
  elseif codepoint == EOF then
    doctype_eof(parser)
  else
    return parser:tokenize("before_doctype_name")
  end
end

HtmlStates.before_doctype_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_doctype_name"
  elseif codepoint == null then
    parser:set_token_data("name", {0xFFFD})
    return "doctype_name"
  elseif codepoint == greater_than then
    parser:set_token_data("force_quirks", true)
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  elseif is_upper_alpha(codepoint) then
    -- add lowercase name
    parser:append_token_data("name", uchar(codepoint + 0x20))
    return "doctype_name"
  else
    parser:append_token_data("name", uchar(codepoint))
    return "doctype_name"
  end
end

HtmlStates.doctype_name = function(parser)

  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "after_doctype_name"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == null then
    parser:append_token_data("name", 0xFFFD)
    return "doctype_name"
  elseif codepoint == EOF then
    doctype_eof(parser)
  elseif is_upper_alpha(codepoint) then
    -- add lowercase name
    parser:append_token_data("name", uchar(codepoint + 0x20))
    return "doctype_name"
  else
    parser:append_token_data("name", uchar(codepoint))
    return "doctype_name"
  end
end

HtmlStates.after_doctype_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "after_doctype_name"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  else
    parser:append_token_data("data", uchar(codepoint))
    -- there are lot of complicated rules how to consume doctype, 
    -- but I think that for our purpose they aren't interesting.
    -- so everything until EOF or > is consumed as token.data
    return "consume_doctype_data"
  end
end

HtmlStates.consume_doctype_data = function(parser)
  -- this state just reads everything inside doctype as data
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser:emit()
    return "data"
  elseif codepoint == EOF then
    doctype_eof(parser)
  else
    parser:append_token_data("data", uchar(codepoint))
    return "consume_doctype_data"
  end
end

HtmlStates.tag_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then 
    return "before_attribute_name"
  elseif codepoint == solidus then
    return "self_closing_tag"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  elseif is_upper_alpha(codepoint) then
    local lower = string.lower(uchar(codepoint))
    parser:append_token_data("name", lower)
  else
    local char = uchar(codepoint)
    parser:append_token_data("name", char)
  end
  return "tag_name"

end

HtmlStates.self_closing_tag = function(parser)
  local codepoint = parser.codepoint
  if codepoint == greater_than then
    parser.current_token.self_closing = true
    parser:emit()
    return "data"
  else
    return parser:tokenize("before_attribute_name")
  end
end


HtmlStates.before_attribute_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    -- ignore spacing
    return "before_attribute_name"
  elseif codepoint == solidus or codepoint == greater_than then
    -- reconsume in after_attribute_name
    return parser:tokenize("after_attribute_name")
  elseif codepoint == equals then
    -- ToDo: handle https://html.spec.whatwg.org/multipage/parsing.html#parse-error-unexpected-equals-sign-before-attribute-name
  else
    -- start new attribute
    parser:start_attribute()
    return parser:tokenize("attribute_name")
  end
end

HtmlStates.attribute_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) 
     or codepoint == solidus
     or codepoint == greater_than 
  then
    return parser:tokenize("after_attribute_name")
  elseif codepoint == equals then
    return "before_attribute_value"
  elseif is_upper_alpha(codepoint) then
    -- lowercase attribute names
    local lower = string.lower(uchar(codepoint))
    parser:append_token_data("current_attr_name", lower)
    return "attribute_name"
  else
    parser:append_token_data("current_attr_name", uchar(codepoint))
    return "attribute_name"
  end
end

HtmlStates.after_attribute_name = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "after_attribute_name"
  elseif codepoint == equals then
    return "before_attribute_value"
  elseif codepoint == solidus then
    return "self_closing_tag"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    parser:start_attribute()
    return parser:tokenize("attribute_name")
  end
end

HtmlStates.before_attribute_value = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_attribute_value" 
  elseif codepoint == quoting then
    return "attribute_value_quoting"
  elseif codepoint == apostrophe then
    return "attribute_value_apostrophe"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    return  parser:tokenize("attribute_value_unquoted")
  end
end

HtmlStates.attribute_value_quoting = function(parser)
  local codepoint = parser.codepoint
  if codepoint == quoting then
    return "after_attribute_value_quoting"
  elseif codepoint == amperesand then
    parser.return_state = "attribute_value_quoting"
    return "character_reference"
  else
    parser:append_token_data("current_attr_value", uchar(codepoint))
    return "attribute_value_quoting"
  end
end

HtmlStates.attribute_value_apostrophe = function(parser)
  local codepoint = parser.codepoint
  if codepoint == apostrophe then
    return "after_attribute_value_quoting"
  elseif codepoint == amperesand then
    parser.return_state = "attribute_value_apostrophe"
    return "character_reference"
  else
    parser:append_token_data("current_attr_value", uchar(codepoint))
    return "attribute_value_apostrophe"
  end
end

HtmlStates.attribute_value_unquoted = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_attribute_name"
  elseif codepoint == amperesand then
    parser.return_state = "attribute_value_unquoted"
    return "character_reference"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else
    parser:append_token_data("current_attr_value", uchar(codepoint))
    return "attribute_value_unquoted"
  end
end

HtmlStates.after_attribute_value_quoting = function(parser)
  local codepoint = parser.codepoint
  if is_space(codepoint) then
    return "before_attribute_name"
  elseif codepoint == solidus then
    return "self_closing_tag"
  elseif codepoint == greater_than then
    parser:emit()
    return "data"
  else 
    return parser:tokenize("before_attribute_name")
  end
end

HtmlStates.rcdata = function(parser)
  -- this is the default state
  local codepoint = parser.codepoint
  -- print("codepoint", parser.codepoint)
  if codepoint == less_than then
    -- start of tag
    return "rcdata_less_than"
  elseif codepoint  == amperesand then
    -- we must save the current state 
    -- what we will return to after entity
    parser.return_state = "rcdata"
    return "character_reference" 
  elseif codepoint == null then
    local data = {char = uchar(0xFFFD)}
    parser:emit_character(uchar(0xFFFD))
  elseif codepoint == EOF then
    parser:start_token("end_of_file", {})
    parser:emit()
  else
    parser:emit_character(uchar(codepoint))
  end
  return "rcdata"
end

local function discard_rcdata_end_tag(parser, text)
    parser:discard_token()
    parser:emit_character(text)
end

HtmlStates.rcdata_less_than = function(parser)
  local codepoint = parser.codepoint
  if codepoint == solidus then
    return "rcdata_end_tag_open"
  else
    discard_rcdata_end_tag(parser, "<")
    return parser:tokenize("rcdata")
  end
end

HtmlStates.rcdata_end_tag_open = function(parser)
  local codepoint = parser.codepoint
  if is_alpha(codepoint) then
    parser:start_token("end_tag", {name={}})
    return parser:tokenize("rcdata_end_tag_name")
  else
    discard_rcdata_end_tag(parser, "</")
    return parser:tokenize("rcdata")
  end
end



HtmlStates.rcdata_end_tag_name = function(parser)
  -- we need to find name of the currently opened tag
  local parent = parser:get_parent() or {}
  local opened_tag = parent.tag 
  local current_tag = table.concat(parser.current_token.name or {})
  local codepoint = parser.codepoint
  if is_upper_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint + 0x20))
    return "rcdata_end_tag_name"
  elseif is_lower_alpha(codepoint) then
    parser:append_token_data("name", uchar(codepoint))
    return "rcdata_end_tag_name"
  elseif opened_tag == current_tag then
    if is_space(codepoint) then
      return "before_attribute_name"
    elseif codepoint == solidus then
      return "self_closing_tag"
    elseif codepoint == greater_than then
      parser:emit()
      return "data"
    end
  else
    discard_rcdata_end_tag(parser, "</" .. current_tag)
    return parser:tokenize("rcdata")
  end
end

HtmlStates.rawtext = function(parser)

end

local HtmlParser = {}

function HtmlParser:init(body)
  local o ={}
  setmetatable(o, self)
  self.__index    = self
  o.body          = self:normalize_newlines(body) -- HTML string
  o.position      = 0                -- position in the parsed string
  o.unfinished    = {Root:init()}    -- insert Root node into the list of opened elements
  o.default_state = "data"           -- default state machine state
  o.state         = o.default_state  -- working state of the machine
  o.return_state  = o.default_state  -- special state set by entities parsing
  o.temp_buffer   = {}               -- keep temporary data
  o.current_token = {type="start"}   -- currently processed token
  return o
end

function HtmlParser:normalize_newlines(body)
  -- we must normalize newlines
  return body:gsub("\r\n", "\n"):gsub("\r", "\n")
end

-- declare void elements
local self_closing_tags_list = {"area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"}
 
local self_closing_tags = {}
for _,v in ipairs(self_closing_tags_list) do self_closing_tags[v] = true end




function HtmlParser:parse()
  -- we assume utf8 input, you must convert it yourself if the source is 
  -- in a different encoding
  self.text = {}
  self.state = self.default_state
  -- this should enable us to pass over some characters that we want to ignore
  -- for example scripts, css, etc.
  self.ignored_pos = -1
  for pos, ucode in utf8.codes(self.body) do
    -- save buffer info and require the tokenize function
    if pos > self.ignored_pos then
      self.position = pos
      self.codepoint = ucode
      self.character = uchar(ucode)
      self.state = self:tokenize(self.state) or self.state -- if tokenizer don't return new state, assume that it continues in the current state
    end
  end
  return self:finish()
end

function HtmlParser:tokenize(state)
  local state = state or self.state
  local ucode = self.codepoint
  local text = self.text

  if ucode == less_than then
    -- state = "in_tag"
     -- self:add_text(text) 
  elseif ucode == greater_than then
    -- state = "data"
    -- self:add_tag(text)
  elseif self.position ~= self.last_position then
    -- self.text[#text+1] = uchar(ucode)
  end
  self.last_position = self.position
  self.element_state = false
  -- execute state machine object and return new state
  local fn = HtmlStates[state] or function(parser) return self.default_state end
  local newstate =  fn(self)
  -- this should enable changing state from elements that needs special treatment, like <script> or <style>
  if self.element_state then return self.element_state end
  -- print("newstate", newstate, state, uchar(ucode or 32))
  return newstate
end

function HtmlParser:start_token(typ, data)
  -- emit the previous token
  self:emit()
  data.type = typ
  self.current_token = data
end

function HtmlParser:discard_token()
  self.current_token = {type="empty"}
end



function HtmlParser:append_token_data(name, data)
  -- append data to the current token
  local token = self.current_token or {}
  if token[name] and type(token[name]) == "table" then
    table.insert(token[name], data)
  end
end

function HtmlParser:set_token_data(name, data)
  local token = self.current_token or {}
  token[name] = data
end

function HtmlParser:flush_temp_buffer()
  -- write stuff from the temp buffer back to the document
  local token = self.current_token
  if token.type == "start_tag" then
    -- in start tag, entities can be only in attribute value
    for _, char in ipairs(self.temp_buffer) do
      table.insert(token.current_attr_value, char)
    end
  elseif self.return_state == "data" then
    -- handle entities in text
    for _, char in ipairs(self.temp_buffer) do
      self:start_token("character", {char=char})
      self:emit()
    end
  end
  self.temp_buffer = {}
end

function HtmlParser:add_entity(char)
  local token = self.current_token
  if token.type == "start_tag" then
    table.insert(token.current_attr_value, char)
  else
    self:start_token("character", {char=char})
    self:emit()
  end
  self.temp_buffer = {}
end

function HtmlParser:emit(token)
  -- state machine functions should use this function to emit tokens
  local token = token or self.current_token
  print("Emit", token.type)
  local token_type = token.type
  if token_type     == "character" then
    table.insert(self.text, token.char)
  elseif token_type == "doctype" then
    self:add_text()
    self:add_doctype()
  elseif token_type == "start_tag" then
    self:add_text()
    -- self:start_attribute()
    self:start_tag()
    print("Emit start tag", table.concat(token.name))
    -- save last attribute
  elseif token_type == "end_tag" then
    self:add_text()
    self:end_tag()
    print("Emit end tag", table.concat(token.name))
  elseif token_type == "comment" then
    self:add_text()
    self:add_comment()
    -- self:start_attribute()
  elseif token_type == "empty" then

  end
  self.current_token = {type="empty"}
end

function HtmlParser:emit_character(text)
  self:start_token("character", {char=text})
  self:emit()
end

function HtmlParser:get_parent()
  -- return parent element
  return self.unfinished[#self.unfinished]
end

function HtmlParser:close_element()
  -- return parent element and remove it from the unfinished list
  return table.remove(self.unfinished)
end

function HtmlParser:add_text(text)
  -- process current text node
  local text = text
  if not text then
    text = self.text
  end
  if type(text) == "table" then
    if #text > 0 then
      text = table.concat(text)
    end
  end
  if type(text) == "string" and text~="" then
    local parent = self:get_parent()
    local node = Text:init(text, parent)
    parent:add_child(node)
  end
  self.text = {}
end

function HtmlParser:get_tag(text)
  local tag = {}
  for _, x in ipairs(text) do 
    if x~=" " then
      tag[#tag+1] = x
    else
      break
    end
  end
  return table.concat(tag)
end

function HtmlParser:start_attribute()
  local token = self.current_token or {}
  if token.type == "start_tag" then
    local attr_name = table.concat(token.current_attr_name)
    local attr_value = table.concat(token.current_attr_value) or ""
    if attr_name ~= "" then
      -- token.attr[attr_name] = attr_value
      table.insert(token.attr, {name = attr_name, value = attr_value})
      print("saving attribute", attr_name, attr_value)
    end
    self:set_token_data("current_attr_name", {})
    self:set_token_data("current_attr_value", {})
  end
end

function HtmlParser:start_tag()
  local token = self.current_token
  if token.type == "start_tag" then
    -- close all currently opened attributes
    self:start_attribute()
    -- initiate Element object, pass attributes and info about self_closing
    local name = table.concat(token.name)
    local parent = self:get_parent()
    local node = Element:init(name, parent)
    node.attr = token.attr
    node.self_closing = token.self_closing
    -- 
    if token.self_closing        -- <img />
      or self_closing_tags[name] -- void elements
    then
      parent:add_child(node)
    else
      -- add to the unfinished list
      table.insert(self.unfinished, node)
    end
    if name == "style" then 
      self.element_state = "rcdata" 
    end
  end
end

function HtmlParser:end_tag()
  -- close current opened element
  local token = self.current_token
  if token.type == "end_tag" then
    if #self.unfinished==1 then return nil end
    local node = self:close_element()
    local parent = self:get_parent()
    parent:add_child(node)
  end
end

function HtmlParser:add_comment()
  local token = self.current_token
  if token.type == "comment" then
    self:start_attribute()
    local parent = self:get_parent()
    local text = table.concat(token.data)
    local node = Comment:init(text, parent)
    parent:add_child(node)
  end
end

function HtmlParser:add_doctype()
  local token = self.current_token
  if token.type == "doctype" then
    self:start_attribute()
    local parent = self:get_parent()
    local name = table.concat(token.name)
    local node = Doctype:init(name, parent)
    if #token.data > 0 then
      node:add_data(table.concat(token.data))
    end
    parent:add_child(node)
  end
end

function HtmlParser:add_tag(text)
  -- this code is obsolete, it is remainder from the older code
  -- main function for handling various tag types
  local tag = self:get_tag(text)
  local first_char = text[1] 
  if first_char == "/" then
    if #self.unfinished==1 then return nil end
    local node = self:close_element()
    local parent = self:get_parent()
    parent:add_child(node)
  elseif first_char == "!" then
    local parent = self:get_parent()
    local node = Doctype:init(text)
    parent:add_child(node)
  elseif text[#text] == "/" then
    -- self closing tag
    local parent = self:get_parent()
    local node = Element:init(text, parent)
    parent:add_child(node)
  elseif self_closing_tags[tag] then
    -- self closing tag
    local parent = self:get_parent()
    local node = Element:init(text, parent)
    parent:add_child(node)
  else
    local parent = self:get_parent()
    local node = Element:init(text, parent)
    table.insert(self.unfinished, node)
  end
  self.text = {}
end

function HtmlParser:finish()
  -- tokenize without any real character
  self.codepoint = EOF
  self:tokenize(self.state)
  self:emit()
  self:add_text()
  -- close all unclosed elements
  if #self.unfinished == 0 then
    -- add implicit html tag
    self:add_tag("html")
  end
  while #self.unfinished > 1 do
    local node = self:close_element()
    local parent = self:get_parent()
    parent:add_child(node)
  end
  -- return root element
  return self:close_element()
end

-- 
M.Text       = Text
M.Element    = Element
M.HtmlParser = HtmlParser
M.HtmlStates = HtmlStates -- table with functions for particular parser states
M.self_closing_tags = self_closing_tags -- list of void elements
M.search_entity_tree = search_entity_tree
return M 
