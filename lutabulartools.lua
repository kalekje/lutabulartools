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


local pl = _G['penlight'] or _G['pl'] -- penlight for this namespace is pl
if (__PL_EXTRAS__ == nil) or  (__PENLIGHT__ == nil) then
    tex.sprint('\\PackageError{yamlvars}{penlight package with extras (or extrasglobals) option must be loaded before this package}{}')
    tex.print('\\stop')
end
local T = pl.tablex

local ltt = {}

ltt.tablelevel = 0

ltt.debug = false

ltt.auto_topbot = false

ltt.auto_crules = {} -- {{span,trim}, } appearance is like this, 'range|trim', -- auto_rules created by MC
ltt.auto_midrules = {}

ltt.col_spec1 = {} -- column spec if one column wide (since makcell nests a tabular, preserve col_spec below)
ltt.col_spec = {} -- tab column spec if above 1
ltt.col = '' -- current column spec, single char, only applies to tabular with more than 1 column
ltt.col_num = 1 -- current column number
ltt.row_num = 0 -- current row number


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



-----
-----       utility funcs
-----


function ltt.debugtalk(s, ss)
    ss = ss or ''
    if ltt.debug then
        pl.tex.help_wrt(s, ss..' (lutabulartools)')
    end
end


function ltt.set_tabular(sett)
    sett = luakeys.parse(sett)
    local trim = ''
    for k, v in pairs(sett) do
        if k == 'tbrule' then
            ltt.auto_topbot = v
        elseif k == 'nopad' then
            if pl.hasval(v) then trim = '@{}' end -- set to trim
            tex.print('\\newcolumntype{\\lttltrim}{'..trim..'}')
            tex.print('\\newcolumntype{\\lttrtrim}{'..trim..'}')
        end
    end
end


-----
-----       tabular utility funcs
-----

function ltt.reset_rows()
    if ltt.tablelevel == 1 then
        ltt.row_num = 0
    end
end

function ltt.set_col_num()
    -- register current column info (column number and specification)
    local nest
    for i = tex.nest.ptr, 1, -1 do
      local tail = tex.nest[i].tail
      if tail.id == node.id'glue' and tail.subtype == table.swapped(node.subtypes'glue').tabskip then
        nest = tex.nest[i]
        break
      end
    end
    if nest then
      local col = 1
      for _, sub in node.traverse_id(node.id'unset', nest.head) do
        col = col + sub + 1
      end
      ltt.col_num = col
    else
      ltt.col_num = 1
    end
    ltt.col = ltt.col_spec[ltt.col_num]
    ltt.debugtalk('col_num='..ltt.col_num..'; col_spec='..ltt.col,'set_col_num')
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
    ltt.debugtalk(ltt.col_spec,'set_col_spec')
end


--todo
-- if p{} column, and multirow is 1, use {=} instead of {*}
-- but note, makecell will not work. So you may want to skip it.multicolumn
-- this case should be considered in this code.
-- for example: \multirow{2}{=}


-----
-----       magic cell and helpers
-----

function ltt.MagicCell(s0,spec,mcspec,pre,content,trim)
    --
    ltt.set_col_num() -- register current column number and column spec

    local STR = ''
    pl.tex.reset_bkt_cnt()

    local v, h, r, c, mrowsym, skipmakecell = ltt.parse_MagicCell_spec(spec) -- get v/h align, number rows/columns

    local mcspec = mcspec or ''

    h, mcspec, c = ltt.get_HColSpec(h, mcspec, c)  -- infer horizontal alignment, num columns

    ltt.debugtalk(pl.List{v, h, r, c, mcspec}:join'; ','v, h, r, c, mcspec')

    --help_wrt(_CurTabColAbv,'current column')
    if s0 == pl.tex._xTrue or (pl.List(ltt.SI_cols):contains(ltt.col) -- special columns for SI
            and c == '') then -- multicolumn cannot have {} around it
        STR = STR .. '{'                                       -- multirow and makcell must have {} around it S column is used
        pl.tex.add_bkt_cnt()
    end

    if c ~= '' then
        STR = STR .. "\\multicolumn{"..c.."}{"..mcspec.."}{"
        pl.tex.add_bkt_cnt()
    end

    if r ~= '' then
        STR = STR .."\\multirow["..v.."]{"..r.."}{"..mrowsym.."}{" -- optional arg here
        pl.tex.add_bkt_cnt()
    end

    if not skipmakecell then
        if pre ~= '' then
            STR = STR.."\\renewcommand{\\cellset}{"..pre.."}"
        end

        STR = STR.."\\makecell[{"..v.."}{"..h.."}]{"
        pl.tex.add_bkt_cnt()
    else
        content = content:gsub('\\\\', '\\newline')
    end

    STR = STR..content..pl.tex.close_bkt_cnt()
    --Troubleshooting
    --help_wrt(STR..' <<< magic cell string')
    ltt.debugtalk(STR,'MagicCell')
    tex.sprint(STR)--tex print the STR

    local en
    if c == '' then en = ltt.col_num else en = ltt.col_num + c -1 end
    ltt.add_auto_crule(ltt.col_num, en, trim)
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


-----
-----       autorules (with \MC() or auto top bot
-----

function ltt.add_auto_midrules(rows)
    ltt.auto_midrules = rows:split(',')
end

function ltt.add_auto_crule(st,en,trim)
    if trim ~= 'x' then
        ltt.auto_crules[#ltt.auto_crules + 1] = {math.floor(st)..'-'..math.floor(en), trim} -- append here
        -- {{span 1-2, trim}, ..}
    end
end


function ltt.process_auto_rules()
    if ltt.tablelevel == 1 then
        ltt.row_num = ltt.row_num + 1
    end
    if ltt.auto_crules ~= {} then
        if ltt.tablelevel == 1 then
            for _, v in ipairs(ltt.auto_crules) do
                --pl.help_wrt(ltt.auto_crules, 'fuck')
                ltt.make1cmidrule('', v[2], v[1], 'cmidrule')
            end
            for i, v in ipairs(ltt.auto_midrules) do
                --pl.help_wrt(ltt.auto_midrules, 'fuck')
                --pl.help_wrt(v, 'fuck')
                pl.help_wrt(ltt.row_num, 'fuck')
                if tonumber(v) == ltt.row_num then
                    _ = table.remove(ltt.auto_midrules,i)
                    --pl.help_wrt(v, 'removed!')
                    tex.print('\\midrule ')
                end
            end
        end
    end
    ltt.auto_crules = {}
end




function ltt.process_auto_topbot_rule(rule)
    if ltt.tablelevel == 1 then
        if ltt.auto_topbot then
            tex.print('\\'..rule..'rule ')
        end
    end
end






-----
-----       midrule and midruleX stuff
-----


ltt.mrX = {}
ltt.mrX.defaults = {step=5, rule='midrule', reset=false, resetnum=0, cntr=0}
ltt.mrX.settings = T.copy(ltt.mrX.defaults)
ltt.mrX.cntr = 0
ltt.mrX.pgcntr = 0



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
    ltt.debugtalk(cmd,'make1cmidrule')
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



function ltt.mrX.set_midruleX(new_sett, def)
    def = def or ''
    local curr_sett = {}
    if def == pl.tex._xTrue then  -- default flag, if true, reset all non-used keys to default
        curr_sett = ltt.mrX.defaults
    else
        curr_sett = ltt.mrX.settings
    end
    new_sett = luakeys.parse(new_sett)
    ltt.mrX.settings = T.union(curr_sett, new_sett)
    ltt.debugtalk(ltt.mrX.settings, 'new midruleX settings')
    ltt.mrX.cntr = curr_sett.cntr
end

function ltt.mrX.midruleX(n)
    n = n or '' -- todo placeholder for noalign ?
    local s = ltt.mrX.settings
    local rule = s.rule
    if pl.hasval(s.reset) and ltt.mrX.add_label_and_check_page_change() then ltt.mrX.cntr = s.resetnum end
    ltt.mrX.cntr = ltt.mrX.cntr + 1
    if ltt.mrX.cntr == s.step then
        if not rule:startswith('\\') then  rule = '\\'..rule end -- todo consider allowing \gmidrule syntax, possible issue with expansion
        ltt.debugtalk(rule, 'apply midruleX')
        tex.sprint(rule)
        ltt.mrX.cntr = 0
    end
end

function ltt.mrX.add_label_and_check_page_change()
    ltt.mrX.pgcntr = ltt.mrX.pgcntr + 1
    tex.print('\\noalign{\\label{ltt@tabular@row@'..ltt.mrX.pgcntr..'}}')
    local rcurr = pl.tex.get_ref_info('ltt@tabular@row@'..ltt.mrX.pgcntr)
    local rprev = pl.tex.get_ref_info('ltt@tabular@row@'..ltt.mrX.pgcntr-1)
    --local rcurrc, _, _ = pl.tex.get_ref_info_all_cref('ltt@tabular@row@'..ltt.mrX.pgcntr)
    ltt.debugtalk('curr: '..rcurr[2]..'   prev: '..rprev[2]..'   row: '..ltt.mrX.pgcntr, 'check midruleX page change')
    ltt.debugtalk(rcurr, 'miduleX current reference info for row: '..ltt.mrX.pgcntr)
    --ltt.debugtalk(rcurrc, 'miduleX current cleveref cref info')
    if  rcurr[2] ~= rprev[2] then  -- pg no is second element
        return true
    end
    return false
end






--
--ltt.tabular_row_pages_cntr = 0
--function ltt.reset_midruleX_on_newpage(n)
--    local n = n or 0
--    ltt.tabular_row_pages_cntr = ltt.tabular_row_pages_cntr + 1
--    tex.print('\\noalign{\\label{tabular@row@'..ltt.tabular_row_pages_cntr..'}}')
--    if ltt.get_ref_page('tabular@row@'..ltt.tabular_row_pages_cntr) -
--            ltt.get_ref_page('tabular@row@'..(ltt.tabular_row_pages_cntr-1)) == 1 then
--      tex.print('\\setcounter{midruleX}{'..n..'}')
--    end
--end


--help_wrt('TEST COL ')
--for _, s in ipairs{ 'll', '*{6}{s}', 'l*{6}{l}', 'lll', 'll[]', 'll[]*{6}{l}', '*{6}{l}', 'y*{6}{sq}x', } do
--    ltt. set_col_spec(s)
--    help_wrt(ltt.col_spec,s)
--end

return ltt -- lutabulartools



--http://ctan.mirror.rafal.ca/macros/latex/contrib/multirow/multirow.pdf
--http://ctan.mirror.colo-serv.net/macros/latex/contrib/makecell/makecell.pdf
-- https://tex.stackexchange.com/questions/331716/newline-in-multirow-environment
