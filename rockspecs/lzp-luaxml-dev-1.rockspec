---@diagnostic disable
package = "lzp-luaxml"
version = "dev-1"
source = {
   url = "git+https://github.com/zepinglee/LuaXML.git"
}
description = {
   summary = "LuaXML is pure lua library for reading and serializing of the XML files.",
   detailed = [[
LuaXML is pure lua library for reading and serializing of the XML files. Current release is aimed mainly as support
for the odsfile package. The documentation was created by automatic conversion of original documentation in the source code.
In this version, some files not useful for luaTeX were droped. ]],
   homepage = "https://github.com/zepinglee/LuaXML",
   license = "MIT"
}
dependencies = {
   "lua >= 5.3, < 5.5"
}
build = {
   type = "builtin",
   modules = {
      ["lzp-luaxml.cssquery"] = "luaxml-cssquery.lua",
      ["lzp-luaxml.domobject"] = "luaxml-domobject.lua",
      ["lzp-luaxml.encodings"] = "luaxml-encodings.lua",
      ["lzp-luaxml.entities"] = "luaxml-entities.lua",
      ["lzp-luaxml.mod-handler"] = "luaxml-mod-handler.lua",
      ["lzp-luaxml.mod-html"] = "luaxml-mod-html.lua",
      ["lzp-luaxml.mod-xml"] = "luaxml-mod-xml.lua",
      ["lzp-luaxml.namedentities"] = "luaxml-namedentities.lua",
      ["lzp-luaxml.parse-query"] = "luaxml-parse-query.lua",
      ["lzp-luaxml.pretty"] = "luaxml-pretty.lua",
      ["lzp-luaxml.stack"] = "luaxml-stack.lua",
      ["lzp-luaxml.testxml"] = "luaxml-testxml.lua",
      ["lzp-luaxml.transform"] = "luaxml-transform.lua",
   }
}
