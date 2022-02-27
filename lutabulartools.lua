--% Kale Ewasiuk (kalekje@gmail.com)
--% +REVDATE+
--% Copyright (C) 2021-2022 Kale Ewasiuk
--%
--% Permission is hereby granted, free of charge, to any person obtaining a copy
--% of this software and associated documentation files (the "Software"), to deal
--% in the Software without restriction, including without limitation the rights
--% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--% copies of the Software, and to permit persons to whom the Software is
--% furnished to do so, subject to the following conditions:
--%
--% The above copyright notice and this permission notice shall be included in
--% all copies or substantial portions of the Software.
--%
--% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
--% ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
--% TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--% PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT
--% SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
--% ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
--% ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
--% OR OTHER DEALINGS IN THE SOFTWARE.

local ltt = {}

ltt.col_spec1 = {} -- column spec if one column wide (since makcell nests a tabular, preserve col_spec below)
ltt.col_spec = {} -- tab column spec if above 1
ltt.col = '' -- current column spec, single char, only applies to tabular with more than 1 column
ltt.col_num = 1 -- current column number


local glue_t, unset_t, tabskip_st = node.id'glue', node.id'unset'
local tabskip_st = table.swapped(node.subtypes'glue').tabskip
assert(tabskip_st)


function ltt.set_col_num()
    -- register current column info (column number and specification)
    local nest
    for i = tex.nest.ptr, 1, -1 do
      local tail = tex.nest[i].tail
      if tail.id == glue_t and tail.subtype == tabskip_st then
        nest = tex.nest[i]
        break
      end
    end
    if nest then
      local col = 1
      for _, sub in node.traverse_id(unset_t, nest.head) do
        col = col + sub + 1
      end
      ltt.col_num = col
    else
      ltt.col_num = 1
    end
    ltt.col = ltt.col_spec[ltt.col_num]
end


function ltt.set_col_spec(zz)
    -- contents of string 'zz'
    -- register the table column specification
    zz = zz:gsub ( "%*%s-{(%d-)}%s-(%b{})" ,     -- expand expressions such as "*{5}{l}" to "lllll"
            function(y, z ) z = z:sub (2 , -2)  return string.rep (z, y) end ) --
    zz = zz:gsub ( "%b{}" , "" ) -- omit all stuff in curly braces and square
    zz = zz:gsub ( "%b[]" , "" )
    zz = zz:gsub ( "[@!|><%s%*\']" , "" )  -- some more characters to ignore
    zz = zz:gsub('%a', ltt.col_replaces) -- sub extra column
    _col_spec = zz:totable() -- requires pl extras
    --help_wrt(_col_spec, 'helpme')
    if #_col_spec > 1 then
        ltt.col_spec = _col_spec
    else
        ltt.col_spec1 = _col_spec
    end
end


--todo
-- if p{} column, and multirow is 1, use {=} instead of {*}
-- but note, makecell will not work. So you may want to skip it.multicolumn
-- this case should be considered in this code.
-- for example: \multirow{2}{=}

function ltt.MagicCell(s0,spec,mcspec,pre,content)
    --
    ltt.set_col_num() -- register current column number and column spec

    local STR = ''
    reset_bkt_cnt()

    local v, h, r, c, mrowsym, skipmakecell = ltt.parse_MagicCell_spec(spec) -- get v/h align, number rows/columns

    local mcspec = mcspec or ''

    h, mcspec, c = ltt.get_HColSpec(h, mcspec, c)  -- infer horizontal alignment, num columns

    --help_wrt(_CurTabColAbv,'current column')
    if s0 == _xTrue or (pl.List(ltt.SI_cols):contains(ltt.col) -- special columns for SI
            and c == '') then -- multicolumn cannot have {} around it
        STR = STR .. '{'                                       -- multirow and makcell must have {} around it S column is used
        add_bkt_cnt()
    end

    if c ~= '' then
        STR = STR .. "\\multicolumn{"..c.."}{"..mcspec.."}{"
        add_bkt_cnt()
    end

    if r ~= '' then
        STR = STR .."\\multirow["..v.."]{"..r.."}{"..mrowsym.."}{" -- optional arg here
        add_bkt_cnt()
    end

    if not skipmakecell then
        if pre ~= '' then
            STR = STR.."\\renewcommand{\\cellset}{"..pre.."}"
        end

        STR = STR.."\\makecell[{"..v.."}{"..h.."}]{"
        add_bkt_cnt()
    else
        content = content:gsub('\\\\', '\\newline')
    end

    STR = STR..content..close_bkt_cnt()
    --Troubleshooting
    --help_wrt(STR..' <<< magic cell string')
    tex.sprint(STR)--tex print the STR
end


function ltt.parse_MagicCell_spec(spec)
    local mrowsym = '*' -- *  = natural width, = will match p{2cm} for example
    local skipmakecell = false
    if string.find(spec, '=')  then
        spec = spec:gsub('=', '')
        mrowsym = '='
        skipmakecell = true
    end

    spec = spec:lower():gsub('%s','')  -- take lower case and remove space
    local vh, rc = spec:gextract('%a')  -- extract characters
    local v = vh:gfirst({'t', 'm', 'b'}) or ltt.col_ver_repl[ltt.col] or 't'
    local h = vh:gfirst({'l', 'c', 'r'}) or ''
    v = v:gsub('m', 'c')

    local rc_ = (rc):split(',')
    local c = rc_[1] or ''  --num columns, width
    local r = rc_[2] or '' --num rows, height
    if c == '0' or c == '1' then c = '' end
    if r == '0' or r == '1' then r = '' end

    return v, h, r, c, mrowsym, skipmakecell
end


function ltt.get_HColSpec(h, mcspec, c) -- take horizontal alignment
    -- c is num columns, h is horizontal alginment,
    --Assumes _TabColNum was calculated previosly
     if c == '+' then  -- fill row to end
        c =  tostring(#ltt.col_spec -  ltt.col_num + 1)
    end
    if h == '' then -- if horizontal not provided, use declared column
        h = ltt.col_hor_repl[ltt.col] or 'l'
    end
    if c ~= '' then -- only make new mcspec if column nums > 0
        if mcspec == '' then -- and if no mcspec was passed
            mcspec = h
            if ltt.col_num == 1 then -- if first column, auto detect padding
                mcspec = '@{}'..mcspec
            end
            if (ltt.col_num + tonumber(c) - 1) == #ltt.col_spec then  -- if end on last column
                mcspec = mcspec..'@{}'
            end
        else -- if mcspec if given, extract the alignment
            ltt.set_col_spec(mcspec)
            h = ltt.col_spec1[1] -- get 1 character column spec from mcspec and override h
        end
    end
    return h, mcspec, c
end



ltt.col_ver_repl = {
m = 'm',
M = 'm',
b = 'b',
}

ltt.col_hor_repl = { -- horizontal cell alignment that multicolumn should use if () or [hori] not passed to func
    l = 'l',
    c = 'c',
    r = 'r',
    p = 'l',
    P = 'c',
    X = 'l',
    Y = 'c',
    Z = 'l',
    N = 'c',
    L = 'l',
    R = 'r',
    C = 'c',
}

-- allow user to place their own replacements in for a table, say if they define a column that expands to multiple
ltt.col_replaces = {
--x = 'lll'
}

ltt.SI_cols = {'S', 'N', 'Q', 'L', 'R'}
--ltt.SI_cols = {'S'}
--ltt.SI_cols = {'N'}





-----
--- midrule stuff
-----

function ltt.get_midrule_col(s)
    if string.find(s, '+')  then
        s = s:gsub('+', '')
        if (s == '') or (s == '0') then
            s = 1
        end
        s = tostring(#ltt.col_spec - tonumber(s) + 1) -- use number of tabular columns above 0,
    end
    return s
end


function ltt.make1cmidrule(s, r, c, cmd) -- s=square r=round c=curly
    cmd = '\\'..cmd
    if s ~= '' then
        cmd = cmd..'['..s..']'
    end
    if r ~= '' then
        cmd = cmd..'('..r..')'
    end
    t = string.split(c, '-')
    if t[2] == '' then
        t[2] = '+'
    end
    if t[2] == nil then
        t[2] = t[1]
    end
    c = ltt.get_midrule_col(t[1])..'-'..ltt.get_midrule_col(t[2])
    cmd = cmd..'{'..c..'}'
    --help_wrt(cmd)
    tex.print(cmd)
end

function ltt.makecmidrules(s, r, c, cmd)
    for k, c1 in pairs(string.split(c, ',')) do
        r1, c2 = c1:gextract('%a')
        if r1 == '' then -- if nothing passed in with the column
            r1 = r -- set to the global value passed in round brackets
        end
        ltt.make1cmidrule(s, r1:strip(), c2:strip(), cmd)
    end
end


--help_wrt('TEST COL ')
--for _, s in ipairs{ 'll', '*{6}{s}', 'l*{6}{l}', 'lll', 'll[]', 'll[]*{6}{l}', '*{6}{l}', 'y*{6}{sq}x', } do
--    ltt. set_col_spec(s)
--    help_wrt(ltt.col_spec,s)
--end

return ltt -- lutabulartools



--http://ctan.mirror.rafal.ca/macros/latex/contrib/multirow/multirow.pdf
--http://ctan.mirror.colo-serv.net/macros/latex/contrib/makecell/makecell.pdf
-- https://tex.stackexchange.com/questions/331716/newline-in-multirow-environment
