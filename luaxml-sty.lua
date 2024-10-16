-- provide global object with all variables we will use
luaxml_sty = {
  current = {
    transformation = "default",
    parameters = {}, -- "parameters" argument for transform:add_action
  },
  packages = {},
  -- we want to support multiple transformation objects, they will be stored here
  transformations = {},
}
luaxml_sty.packages.transform = require "luaxml-transform"
luaxml_sty.packages.domobject = require "luaxml-domobject"

-- declare default transformer, used if no explicit transformer is used in LuaXML LaTeX commands
luaxml_sty.transformations.default = luaxml_sty.packages.transform.new()

-- debuggind functions
function luaxml_sty.error(...)
  local arg = {...}
  print("LuaXML error: " .. table.concat(arg, " "))
end

luaxml_sty.do_debug = false

function luaxml_sty.debug(...)
  if luaxml_sty.do_debug then
    local arg = {...}
    print("LuaXML: " .. table.concat(arg, " "))
  end
end



-- add luaxml-transform rule
function luaxml_sty.add_rule(current, selector, rule)
  if current == "" then
   current = luaxml_sty.current.transformation
  end
  -- the +v parameter type in LaTeX replaces newlines with \obeyedline. we need to replace it back to newlines
  rule = rule:gsub("\\obeyedline", "\n")
  luaxml_sty.debug("************* luaxml_sty rule: " .. selector, rule, current, (luaxml_sty.current.parameters.verbatim and "verbatim" or "not verbatim"))
  local transform = luaxml_sty.transformations[current]
  if not transform then
    luaxml_sty.error("Cannot find LuaXML transform object: " .. (current or ""))
    return nil, "Cannot find LuaXML transform object: " .. (current or "")
  end
  transform:add_action(selector, rule, luaxml_sty.current.parameters)
end

-- by default, we will use XML parser, so use_xml is set to true
luaxml_sty.use_xml = true

function luaxml_sty.set_xml()
  luaxml_sty.use_xml = true
end


function luaxml_sty.set_html()
  luaxml_sty.use_xml = false
end

--- transform XML string
function luaxml_sty.parse_snippet(current, xml_string)
  local domobject = luaxml_sty.packages.domobject
  if current == "" then
    current = luaxml_sty.current.transformation
  end
  local transform = luaxml_sty.transformations[current]
  local dom
  if luaxml_sty.use_xml then
    dom = domobject.parse(xml_string)
  else
    dom = domobject.html_parse(xml_string)
  end
  luaxml_sty.debug(dom:serialize())
  local result = transform:process_dom(dom)
  luaxml_sty.packages.transform.print_tex(result)
end

function luaxml_sty.parse_file(current, filename)
  local f = io.open(filename, "r")
  if not f then
    luaxml_sty.packages.transform.print_tex("\\textbf{LuaXML error}: cannot find file " .. filename)
    return nil, "Cannot find file " .. filename
  end
  local content = f:read("*a")
  f:close()
  luaxml_sty.parse_snippet(current, content)
end

--- parse environment contents using Lua
-- idea from https://tex.stackexchange.com/a/574323/2891
function luaxml_sty.store_lines(env_name, callback_name)
  return function(str)
    luaxml_sty.debug("str", str)
    local env_str = [[\end{]] .. env_name .. "}"
    if string.find (str , env_str:gsub("%*", "%%*")) then
      luaxml_sty.debug("end of environment")
      luatexbase.remove_from_callback ( "process_input_buffer" , callback_name)
      return env_str -- str
    else
      table.insert(luaxml_sty.verb_table, str)
    end
    return ""
  end
end

function luaxml_sty.register_verbatim(env_name)
  luaxml_sty.verb_table = {}
  local callback_name = "luaxml_store_lines_".. env_name
  local fn = luaxml_sty.store_lines(env_name, callback_name)
  luatexbase.add_to_callback(
    "process_input_buffer" , fn , callback_name)
end

function luaxml_sty.print_verbatim(transformer)
  luaxml_sty.parse_snippet(transformer, table.concat(luaxml_sty.verb_table, "\n"))
end

return luaxml_sty
