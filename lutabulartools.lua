--% Kale Ewasiuk (kalekje@gmail.com)
--% +REVDATE+
--% Copyright (C) 2021-2023 Kale Ewasiuk
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




local lutabt = {}

local pl = penlight
local T = pl.tablex

lutabt.luakeys = require'luakeys'()  -- note: YAMLvars.sty will have checked existence of this already


lutabt.tablelevel = 0

lutabt.debug = false

lutabt.auto_topbot = false
lutabt.auto_topbot_old = false

lutabt.auto_crules = {} -- {{span,trim}, } appearance is like this, 'range|trim', -- auto_rules created by MC
lutabt.auto_midrules = {}

lutabt.col_spec1 = {} -- column spec if one column wide (since makcell nests a tabular, preserve col_spec below)
lutabt.col_spec = {} -- tab column spec if above 1
lutabt.col = '' -- current column spec, single char, only applies to tabular with more than 1 column
lutabt.col_num = 1 -- current column number
lutabt.row_num = 0 -- current row number

lutabt.actlvl = 1 -- 'active' level on which to apply midrules, normally 1

lutabt.col_ver_repl = {
m = 'm',
M = 'm',
b = 'b',
}

lutabt.col_hor_repl = { -- horizontal cell alignment that multicolumn should use if () or [hori] not passed to func
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
lutabt.col_replaces = {
--x = 'lll'
}

lutabt.SI_cols = {'S', 'N', 'Q', 'L', 'R'}



-----
-----       utility funcs
-----


function lutabt.debugtalk(s, ss)
    ss = ss or ''
    if lutabt.debug then
        pl.tex.help_wrt(s, ss..' (lutabulartools)')
    end
end

function __lutabt__debugprtall()
    pl.help_wrt(lutabt, '(lutabulartools state)')
end


function lutabt.set_tabular(sett)
    sett = lutabt.luakeys.parse(sett)
    local trim = ''
    for k, v in pairs(sett) do
        if k == 'tbrule' then
            lutabt.auto_topbot = v
        elseif k == 'nopad' then
            if pl.hasval(v) then trim = '@{}' end -- set to trim
            tex.print('\\newcolumntype{\\lttltrim}{'..trim..'}')
            tex.print('\\newcolumntype{\\lttrtrim}{'..trim..'}')
        elseif k =='rowsep' then
            tex.print('\\gdef\\arraystretch{'..v..'}')
        elseif k =='colsep' then
            tex.print('\\global\\setlength{\\tabcolsep}{'..(v*6)..'pt'..'}')
        end
    end
end


-----
-----       tabular utility funcs
-----

function lutabt.reset_rows()
    if lutabt.isactlevel() then
        lutabt.row_num = 0
    end
end

function lutabt.set_col_num()
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
      lutabt.col_num = col
    else
      lutabt.col_num = 1
    end
    lutabt.col = lutabt.col_spec[lutabt.col_num]
    lutabt.debugtalk('col_num='..lutabt.col_num..'; col_spec='..lutabt.col,'set_col_num')
end


function lutabt.set_col_spec(zz)
    -- contents of string 'zz'
    -- register the table column specification
    zz = zz:gsub ( "%*%s-{(%d-)}%s-(%b{})" ,     -- expand expressions such as "*{5}{l}" to "lllll"
            function(y, z ) z = z:sub (2 , -2)  return string.rep (z, y) end ) --
    zz = zz:gsub ( "%b{}" , "" ) -- omit all stuff in curly braces and square
    zz = zz:gsub ( "%b[]" , "" )
    zz = zz:gsub ( "[@!|><%s%*\']" , "" )  -- some more characters to ignore
    zz = zz:gsub('%a', lutabt.col_replaces) -- sub extra column
    _col_spec = zz:totable() -- requires pl extras
    --help_wrt(_col_spec, 'helpme')
    if #_col_spec > 1 then
        lutabt.col_spec = _col_spec
    else
        lutabt.col_spec1 = _col_spec
    end
    lutabt.debugtalk(lutabt.col_spec,'set_col_spec')
end


--todo
-- if p{} column, and multirow is 1, use {=} instead of {*}
-- but note, makecell will not work. So you may want to skip it.multicolumn
-- this case should be considered in this code.
-- for example: \multirow{2}{=}


-----
-----       magic cell and helpers
-----

function lutabt.MagicCell(s0,spec,mcspec,pre,content,trim)
    -- todo delete trim!!!
    --
    lutabt.set_col_num() -- register current column number and column spec

    local STR = ''
    pl.tex.reset_bkt_cnt()

    local spec, iscmidrule, trim = lutabt.check_MC_cmidrule(spec) -- check for cmidrule and clean spec

    local v, h, r, c, mrowsym, skipmakecell = lutabt.parse_MagicCell_spec(spec) -- get v/h align, number rows/columns

    local mcspec = mcspec or ''

    h, mcspec, c = lutabt.get_HColSpec(h, mcspec, c)  -- infer horizontal alignment, num columns

    lutabt.debugtalk(pl.List{v, h, r, c, mcspec}:join'; ','v, h, r, c, mcspec')

    --help_wrt(_CurTabColAbv,'current column')
    if s0 == pl.tex._xTrue or (pl.List(lutabt.SI_cols):contains(lutabt.col) -- special columns for SI
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
    lutabt.debugtalk(STR,'MagicCell')
    tex.sprint(STR)--tex print the STR

    if iscmidrule then
        local en
        if c == '' then en = lutabt.col_num else en = lutabt.col_num + c -1 end
        lutabt.add_auto_crule(lutabt.col_num, en, trim)
    end
end


function lutabt.check_MC_cmidrule(spec)
    local iscmidrule = false
    local trim = ''
    local st, en = spec:find('_')
    if st ~= nil then
        trim = spec:sub(st+1, #spec)
        spec = spec:sub(1,st-1)
        iscmidrule = true
    end
    return spec, iscmidrule, trim
end

function lutabt.parse_MagicCell_spec(spec)
    local mrowsym = '*' -- *  = natural width, = will match p{2cm} for example
    local skipmakecell = false
    if string.find(spec, '=')  then
        spec = spec:gsub('=', '')
        mrowsym = '='
        skipmakecell = true
    end

    spec = spec:lower():gsub('%s','')  -- take lower case and remove space
    local vh, rc = spec:gextract('%a')  -- extract characters
    local v = vh:gfirst({'t', 'm', 'b'}) or lutabt.col_ver_repl[lutabt.col] or 't'
    local h = vh:gfirst({'l', 'c', 'r'}) or ''
    v = v:gsub('m', 'c')

    local rc_ = (rc):split(',')
    local c = rc_[1] or ''  --num columns, width
    local r = rc_[2] or '' --num rows, height
    if c == '0' or c == '1' then c = '' end
    if r == '0' or r == '1' then r = '' end

    return v, h, r, c, mrowsym, skipmakecell
end


function lutabt.get_HColSpec(h, mcspec, c) -- take horizontal alignment
    -- c is num columns, h is horizontal alginment,
    --Assumes _TabColNum was calculated previosly
     if c == '+' then  -- fill row to end
        c =  tostring(#lutabt.col_spec -  lutabt.col_num + 1)
    end
    if h == '' then -- if horizontal not provided, use declared column
        h = lutabt.col_hor_repl[lutabt.col] or 'l'
    end
    if c ~= '' then -- only make new mcspec if column nums > 0
        if mcspec == '' then -- and if no mcspec was passed
            mcspec = h
            if lutabt.col_num == 1 then -- if first column, auto detect padding
                mcspec = '@{}'..mcspec
            end
            if (lutabt.col_num + tonumber(c) - 1) == #lutabt.col_spec then  -- if end on last column
                mcspec = mcspec..'@{}'
            end
        else -- if mcspec if given, extract the alignment
            lutabt.set_col_spec(mcspec)
            h = lutabt.col_spec1[1] -- get 1 character column spec from mcspec and override h
        end
    end
    return h, mcspec, c
end


-----
-----       autorules (with \MC() or auto top bot or midrule X, performed after \\
-----

function lutabt.add_auto_midrules(rows)
    lutabt.auto_midrules = rows:split(',')
end

function lutabt.add_auto_crule(st,en,trim)
    if trim ~= 'x' then
        lutabt.auto_crules[#lutabt.auto_crules + 1] = {math.floor(st)..'-'..math.floor(en), trim} -- append here
        -- {{span 1-2, trim}, ..}
    end
end

function lutabt.isactlevel()
    lutabt.tablelevel = tonumber(lutabt.tablelevel)
    lutabt.actlvl = tonumber(lutabt.actlvl)
    return lutabt.actlvl == lutabt.tablelevel
end


function lutabt.process_auto_rules()
    if lutabt.isactlevel() then
        lutabt.row_num = lutabt.row_num + 1
        if lutabt.auto_crules ~= {} then
            for _, v in ipairs(lutabt.auto_crules) do
                lutabt.make1cmidrule('', v[2], v[1], 'cmidrule')
            end
            for i, v in ipairs(lutabt.auto_midrules) do
                if tonumber(v) == lutabt.row_num then
                    _ = table.remove(lutabt.auto_midrules,i)
                    tex.print('\\midrule ')
                end
            end
        end
        if lutabt.mrX.settings.on then
            lutabt.mrX.midruleX()
        end
    end
    lutabt.auto_crules = {}
end




function lutabt.process_auto_topbot_rule(rule)
    if lutabt.isactlevel() then
        if lutabt.auto_topbot then
            tex.print('\\'..rule..'rule ')
        end
    end
end






-----
-----       extra midrule
-----



function lutabt.get_midrule_col(s)
    if string.find(s, '+')  then
        s = s:gsub('+', '')
        if (s == '') or (s == '0') then
            s = 1
        end
        s = tostring(#lutabt.col_spec - tonumber(s) + 1) -- use number of tabular columns above 0,
    end
    return s
end


function lutabt.make1cmidrule(s, r, c, cmd) -- s=square r=round c=curly
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
    c = lutabt.get_midrule_col(t[1])..'-'..lutabt.get_midrule_col(t[2])
    cmd = cmd..'{'..c..'}'
    lutabt.debugtalk(cmd,'make1cmidrule')
    tex.print(cmd)
end

function lutabt.makecmidrules(s, r, c, cmd)
    for k, c1 in pairs(string.split(c, ',')) do
        r1, c2 = c1:gextract('%a')
        if r1 == '' then -- if nothing passed in with the column
            r1 = r -- set to the global value passed in round brackets
        end
        lutabt.make1cmidrule(s, r1:strip(), c2:strip(), cmd)
    end
end


-----
-----         midruleX
-----

lutabt.mrX = {}
lutabt.mrX.resets = {long=false, cntr=0, head=nil, longx=false, on=true} -- settings that reset when \setmidruleX used
lutabt.mrX.resets['head*'] = nil
lutabt.mrX.settings = T.update(T.copy(lutabt.mrX.resets), {pgcntr=0, step=5, rule='midrule'}) -- current settings, not overwritten with each call
lutabt.mrX.settings.on = false

function lutabt.mrX.reset_midruleX(n)
    lutabt.mrX.settings.cntr = tonumber(n)
end

function lutabt.mrX.off()
    if lutabt.isactlevel() then
        lutabt.mrX.settings.on = false
    end
end

function lutabt.mrX.set_midruleX(new_sett, def)
    lutabt.mrX.settings = T.update(lutabt.mrX.settings, T.union(lutabt.mrX.resets, lutabt.luakeys.parse(new_sett)))
    lutabt.debugtalk(lutabt.mrX.settings, 'new midruleX settings')
    if lutabt.mrX.settings.head ~= nil then
        lutabt.mrX.settings.cntr = -1*tonumber(lutabt.mrX.settings.head)
    elseif lutabt.mrX.settings['head*'] ~= nil then
        lutabt.mrX.settings.cntr = -1*tonumber(lutabt.mrX.settings['head*'])
       lutabt.auto_midrules[#lutabt.auto_midrules + 1] =  lutabt.mrX.settings['head*']
        lutabt.mrX.settings['head*'] = nil -- for some reason need to do this to clear head*
    end
    if lutabt.mrX.settings.longx then -- longtable X messes with the tablelevel settings, hack to fix, use longx keyword
        lutabt.actlvl = 3
        lutabt.mrX.settings.long = true
    else
        lutabt.actlvl = 1
    end
end


function lutabt.mrX.midruleX(n)
    n = n or '' -- todo placeholder for noalign ?
    lutabt.debugtalk(lutabt.mrX.settings, 'midruleX here')
    local s = lutabt.mrX.settings
    local rule = s.rule
    if pl.hasval(s.long) and lutabt.mrX.add_label_and_check_page_change() then lutabt.mrX.settings.cntr = 0 end -- reset to number on page change --  longhead not used anymore
    lutabt.mrX.settings.cntr = lutabt.mrX.settings.cntr + 1
    if lutabt.mrX.settings.cntr == s.step then
        if not rule:startswith('\\') then  rule = '\\'..rule end -- todo consider allowing \gmidrule syntax, possible issue with expansion
        lutabt.debugtalk(rule, 'apply midruleX')
        tex.sprint(rule)
        lutabt.mrX.settings.cntr = 0
    end
end

function lutabt.mrX.add_label_and_check_page_change()
    lutabt.mrX.settings.pgcntr = lutabt.mrX.settings.pgcntr + 1
    tex.print('\\noalign{\\label{ltt@tabular@row@'..lutabt.mrX.settings.pgcntr..'}}')
    local rcurr = pl.tex.get_ref_info('ltt@tabular@row@'..lutabt.mrX.settings.pgcntr)
    local rprev = pl.tex.get_ref_info('ltt@tabular@row@'..lutabt.mrX.settings.pgcntr-1)
    --local rcurrc, _, _ = pl.tex.get_ref_info_all_cref('ltt@tabular@row@'..lutabt.mrX.settings.pgcntr)
    lutabt.debugtalk('curr: '..rcurr[2]..'   prev: '..rprev[2]..'   row: '..lutabt.mrX.settings.pgcntr, 'check midruleX page change')
    lutabt.debugtalk(rcurr, 'miduleX current reference info for row: '..lutabt.mrX.settings.pgcntr)
    --lutabt.debugtalk(rcurrc, 'miduleX current cleveref cref info')
    if  rcurr[2] ~= rprev[2] then  -- pg no is second element
        return true
    end
    return false
end


return lutabt -- lutabulartools



--http://ctan.mirror.rafal.ca/macros/latex/contrib/multirow/multirow.pdf
--http://ctan.mirror.colo-serv.net/macros/latex/contrib/makecell/makecell.pdf
-- https://tex.stackexchange.com/questions/331716/newline-in-multirow-environment






