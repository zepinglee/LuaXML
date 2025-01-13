local function letter_to_numeric(patch)
  local patch_number = 0
  patch = patch:lower()
  for i = 1, #patch do
    local c = patch:sub(i, i)
    if c >= "a" and c <= "z" then
      patch_number = patch_number * 26 + string.byte(c) - 96
    end
  end
  return tostring(patch_number)
end


local function to_sematic_version(tag)
  local major, minor, patch, suffix = tag:match("(%d+)%.(%d+)%.(%d+)([0-9A-Za-z.+-]*)")
  if major then
    -- `v0.1.18-beta.1+build.20130313144700`
    return string.format("%s.%s.%s%s", major, minor, patch, suffix)
  end

  major, minor, patch, suffix = tag:match("(%d+)%.(%d+)([A-Za-z]*)([0-9A-Za-z.+-]*)")
  if major then
    -- `v0.1r`
    patch = letter_to_numeric(patch)
    return string.format("%s.%s.%s%s", major, minor, patch, suffix)
  end

  major, minor, suffix = tag:match("(%d+)([A-Za-z]*)([0-9A-Za-z.+-]*)")
  if major then
    -- `v1`
    minor = letter_to_numeric(minor)
    return string.format("%s.%s.%s%s", major, minor, "0", suffix)
  end
  return "0.0.1"
end


local function main()
  print(to_sematic_version(arg[1]))
end


main()
