" vim:tabstop=2:shiftwidth=2:expandtab:textwidth=99
" Vimwiki filetype plugin file
" Home: https://github.com/vimwiki/vimwiki/


" Clause: load only once per buffer
if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1  " Don't load another plugin for this buffer

if vimwiki#vars#get_global('conceallevel') && exists('+conceallevel')
  let &l:conceallevel = vimwiki#vars#get_global('conceallevel')
endif

" This is for GOTO FILE: gf
execute 'setlocal suffixesadd='.vimwiki#vars#get_wikilocal('ext')
setlocal isfname-=[,]

exe 'setlocal tags+=' . escape(vimwiki#tags#metadata_file_path(), ' \|"')


" Helper: for omnicompletion
function! Complete_wikifiles(findstart, base) abort
  " s:line_context = link | tag | ''
  if a:findstart == 1
    " Find line context
    " Called: first time
    let column = col('.')-2
    let line = getline('.')[:column]

    " Check Link:
    " -- WikiLink
    let startoflink = match(line, '\[\[\zs[^\\[\]]*$')
    if startoflink != -1
      let s:line_context = 'link'
      return startoflink
    endif
    " -- WebLink
    if vimwiki#vars#get_wikilocal('syntax') ==? 'markdown'
      let startofinlinelink = match(line, '\[.*\](\zs[^)]*$')
      if startofinlinelink != -1
        let s:line_context = 'link'
        return startofinlinelink
      endif
    endif

    " Check Tag:
    let tf = vimwiki#vars#get_syntaxlocal('tag_format')
    let startoftag = match(line, tf.pre_mark . '\zs' . tf.in . '*$')
    if startoftag != -1
      let s:line_context = 'tag'
      return startoftag
    endif

    " Nothing can do ...
    let s:line_context = ''
    return -1
  else
    " Completion works for wikilinks/anchors, and for tags. s:line_content
    " tells us which string came before a:base. There seems to be no easier
    " solution, because calling col('.') here returns garbage.
    if s:line_context ==? ''
      return []
    elseif s:line_context ==# 'tag'
      " Look Tags: completion
      let tags = vimwiki#tags#get_tags()
      if a:base !=? ''
        call filter(tags,
            \ 'v:val[:' . (len(a:base)-1) . "] == '" . substitute(a:base, "'", "''", '') . "'" )
      endif
      return tags
    elseif a:base !~# '#'
      " Look Wiki: files
      if a:base =~# '\m^wiki\d\+:'
        let wikinumber = eval(matchstr(a:base, '\m^wiki\zs\d\+'))
        if wikinumber >= vimwiki#vars#number_of_wikis()
          return []
        endif
        let prefix = matchstr(a:base, '\m^wiki\d\+:\zs.*')
        let scheme = matchstr(a:base, '\m^wiki\d\+:\ze')
      elseif a:base =~# '^diary:'
        let wikinumber = -1
        let prefix = matchstr(a:base, '^diary:\zs.*')
        let scheme = matchstr(a:base, '^diary:\ze')
      else " current wiki
        let wikinumber = vimwiki#vars#get_bufferlocal('wiki_nr')
        let prefix = a:base
        let scheme = ''
      endif

      let links = vimwiki#base#get_wikilinks(wikinumber, 1, '')
      let result = []
      for wikifile in links
        if wikifile =~ '^'.vimwiki#u#escape(prefix)
          call add(result, scheme . wikifile)
        endif
      endfor
      return result

    else
      " Look Anchor: in the given wikifile

      let segments = split(a:base, '#', 1)
      let given_wikifile = segments[0] ==? '' ? expand('%:t:r') : segments[0]
      let link_infos = vimwiki#base#resolve_link(given_wikifile.'#')
      let wikifile = link_infos.filename
      let syntax = vimwiki#vars#get_wikilocal('syntax', link_infos.index)
      let anchors = vimwiki#base#get_anchors(wikifile, syntax)

      let filtered_anchors = []
      let given_anchor = join(segments[1:], '#')
      for anchor in anchors
        if anchor =~# '^'.vimwiki#u#escape(given_anchor)
          call add(filtered_anchors, segments[0].'#'.anchor)
        endif
      endfor
      return filtered_anchors

    endif
  endif
endfunction

" Set Completion:
setlocal omnifunc=Complete_wikifiles
if and(vimwiki#vars#get_global('emoji_enable'), 2) != 0
      \ && &completefunc ==# ''
  set completefunc=vimwiki#emoji#complete
endif


" Declare Settings: necessary for the automatic formatting of lists
" ------------------------------------------------
setlocal autoindent
setlocal nosmartindent
setlocal nocindent

" Set Comments: to insert and format 'comments' or cheat
" Used to break blockquote prepending one on each new line (see: #915)
" B like blank character follow
" blockquotes
let comments = 'b:>'
for bullet in vimwiki#vars#get_syntaxlocal('bullet_types')
  " task list
  for point in vimwiki#vars#get_wikilocal('listsyms_list')
        \ + [vimwiki#vars#get_wikilocal('listsym_rejected')]
    let comments .= ',fb:' . bullet . ' [' . point . ']'
  endfor
  " list
  let comments .= ',fb:' . bullet
endfor
" Add :: for vimwiki default syntax (#1279)
if 'default' ==# vimwiki#vars#get_wikilocal('syntax')
  let comments .= ',b:::'
endif
let &l:comments = comments

" Set Format Options: (:h fo-table)
" Disable autocomment because, vimwiki does it better
setlocal formatoptions-=r
setlocal formatoptions-=o
setlocal formatoptions-=2
" Autowrap with leading comment
setlocal formatoptions+=c
" Do not wrap if line was already long
setlocal formatoptions+=l
" AutoWrap intelligent with lists
setlocal formatoptions+=n
let &formatlistpat = vimwiki#vars#get_wikilocal('rxListItem')
" Used to join 'commented' lines (blockquote, list) (see: #915)
if v:version > 703
  setlocal formatoptions+=j
endif

" Set commentstring %%%s
let &l:commentstring = vimwiki#vars#get_wikilocal('commentstring')


" ------------------------------------------------
" Folding stuff
" ------------------------------------------------

" Get fold level for a list
function! VimwikiFoldListLevel(lnum) abort
  return vimwiki#lst#fold_level(a:lnum)
endfunction


" Get fold level for 1. line number
function! VimwikiFoldLevel(lnum) abort
  let line = getline(a:lnum)

  " Header/section folding...
  if line =~# vimwiki#vars#get_syntaxlocal('rxHeader') && !vimwiki#u#is_codeblock(a:lnum)
    return '>'.vimwiki#u#count_first_sym(line)
  endif

  " Code block folding...
  " -- previously it would always increment when it saw a ```, so we never left the code block. (See #1323)
  let prevline = getline(v:lnum - 1)
  let nextline = getline(v:lnum + 1)

  " -- Start: assumes empty line before
  if line =~# vimwiki#vars#get_syntaxlocal('rxPreStart') && prevline =~# '^\s*$'
    return 'a1'
  " -- End: assumes empty line after
  elseif line =~# vimwiki#vars#get_syntaxlocal('rxPreEnd') && nextline =~# '^\s*$'
    return 's1'
  endif

  return '='
endfunction


" Declare Constants: used by VimwikiFoldText
" use \u2026 and \u21b2 (or \u2424) if enc=utf-8 to save screen space
let s:ellipsis = (&encoding ==? 'utf-8') ? "\u2026" : '...'
let s:ell_len = strlen(s:ellipsis)
let s:newline = (&encoding ==? 'utf-8') ? "\u21b2 " : '  '
let s:tolerance = 5


" unused: too naive
function! s:shorten_text_simple(text, len) abort
  let spare_len = a:len - len(a:text)
  return (spare_len>=0) ? [a:text,spare_len] : [a:text[0:a:len].s:ellipsis, -1]
endfunction


" Shorten Text:
" Called: by VimwikiFoldText
" s:shorten_text(text, len) = [string, spare] with "spare" = len-strlen(string)
" for long enough "text", the string's length is within s:tolerance of "len"
" (so that -s:tolerance <= spare <= s:tolerance, "string" ends with s:ellipsis)
" Return: [string, spare]
function! s:shorten_text(text, len) abort
  " strlen() returns length in bytes, not in characters, so we'll have to do a
  " trick here -- replace all non-spaces with dot, calculate lengths and
  " indexes on it, then use original string to break at selected index.
  let text_pattern = substitute(a:text, '\m\S', '.', 'g')
  let spare_len = a:len - strlen(text_pattern)
  if (spare_len + s:tolerance >= 0)
    return [a:text, spare_len]
  endif
  " try to break on a space; assumes a:len-s:ell_len >= s:tolerance
  let newlen = a:len - s:ell_len
  let idx = strridx(text_pattern, ' ', newlen + s:tolerance)
  let break_idx = (idx + s:tolerance >= newlen) ? idx : newlen
  return [matchstr(a:text, '\m^.\{'.break_idx.'\}').s:ellipsis, newlen - break_idx]
endfunction


" Fold: text chapter
function! VimwikiFoldText() abort
  let line = getline(v:foldstart)
  let main_text = substitute(line, '^\s*', repeat(' ',indent(v:foldstart)), '')
  let fold_len = v:foldend - v:foldstart + 1
  let len_text = ' ['.fold_len.'] '
  if line !~# vimwiki#vars#get_syntaxlocal('rxPreStart')
    let [main_text, spare_len] = s:shorten_text(main_text, 50)
    return main_text.len_text
  else
    " fold-text for code blocks: use one or two of the starting lines
    let [main_text, spare_len] = s:shorten_text(main_text, 24)
    let line1 = substitute(getline(v:foldstart+1), '^\s*', ' ', '')
    let [content_text, spare_len] = s:shorten_text(line1, spare_len+20)
    if spare_len > s:tolerance && fold_len > 3
      let line2 = substitute(getline(v:foldstart+2), '^\s*', s:newline, '')
      let [more_text, spare_len] = s:shorten_text(line2, spare_len+12)
      let content_text .= more_text
    endif
    return main_text.len_text.content_text
  endif
endfunction



" ------------------------------------------------
" Commands
" ------------------------------------------------

command! -buffer Vimwiki2HTML
      \ if filewritable(expand('%')) | silent noautocmd w | endif
      \ <bar>
      \ let res = vimwiki#html#Wiki2HTML(
      \   expand(vimwiki#vars#get_wikilocal('path_html')), expand('%'))
      \ <bar>
      \ if res != '' | call vimwiki#u#echo('HTML conversion is done, output: '
      \      . expand(vimwiki#vars#get_wikilocal('path_html'))) | endif

command! -buffer Vimwiki2HTMLBrowse
      \ if filewritable(expand('%')) | silent noautocmd w | endif
      \ <bar>
      \ call vimwiki#base#system_open_link(vimwiki#html#Wiki2HTML(
      \         expand(vimwiki#vars#get_wikilocal('path_html')),
      \         expand('%')))

command! -buffer -bang VimwikiAll2HTML
      \ call vimwiki#html#WikiAll2HTML(expand(vimwiki#vars#get_wikilocal('path_html')), <bang>0)

command! -buffer VimwikiRss call vimwiki#html#diary_rss()

command! -buffer VimwikiTOC call vimwiki#base#table_of_contents(1)

command! -buffer VimwikiNextTask call vimwiki#base#find_next_task()
command! -buffer VimwikiNextLink call vimwiki#base#find_next_link()
command! -buffer VimwikiPrevLink call vimwiki#base#find_prev_link()
command! -buffer VimwikiDeleteFile call vimwiki#base#delete_link()
command! -buffer VimwikiDeleteLink
      \ call vimwiki#u#deprecate("VimwikiDeleteLink", "VimwikiDeleteFile") |
      \ call vimwiki#base#delete_link()
command! -buffer -nargs=? -complete=customlist,vimwiki#base#complete_file
      \ VimwikiRenameFile call vimwiki#base#rename_file(<f-args>)
command! -buffer VimwikiRenameLink
      \ call vimwiki#u#deprecate("VimwikiRenameLink", "VimwikiRenameFile") |
      \ call vimwiki#base#rename_file()
command! -buffer VimwikiFollowLink call vimwiki#base#follow_link('nosplit', 0, 1)
command! -buffer VimwikiGoBackLink call vimwiki#base#go_back_link()
command! -buffer -nargs=* VimwikiSplitLink call vimwiki#base#follow_link('hsplit', <f-args>)
command! -buffer -nargs=* VimwikiVSplitLink call vimwiki#base#follow_link('vsplit', <f-args>)
command! -buffer VimwikiBaddLink call vimwiki#base#follow_link('badd', 0, 1)

command! -buffer -nargs=? VimwikiNormalizeLink call vimwiki#base#normalize_link(<f-args>)

command! -buffer VimwikiTabnewLink call vimwiki#base#follow_link('tab', 0, 1)

command! -buffer VimwikiTabDropLink call vimwiki#base#follow_link('tabdrop', 0, 1)

command! -buffer -nargs=? VimwikiGenerateLinks call vimwiki#base#generate_links(1, <f-args>)

command! -buffer -nargs=0 VimwikiBacklinks call vimwiki#base#backlinks()
command! -buffer -nargs=0 VWB call vimwiki#base#backlinks()

command! -buffer -nargs=* VimwikiSearch call vimwiki#base#search(<q-args>)
command! -buffer -nargs=* VWS call vimwiki#base#search(<q-args>)

command! -buffer -nargs=* -complete=customlist,vimwiki#base#complete_links_raw
      \ VimwikiGoto call vimwiki#base#goto(<q-args>)

command! -buffer -range VimwikiCheckLinks call vimwiki#base#check_links(<range>, <line1>, <line2>)

" list commands
command! -buffer -nargs=+ VimwikiReturn call <SID>CR(<f-args>)
command! -buffer -range -nargs=1 VimwikiChangeSymbolTo
      \ call vimwiki#lst#change_marker(<line1>, <line2>, <f-args>, 'n')
command! -buffer -range -nargs=1 VimwikiListChangeSymbolI
      \ call vimwiki#lst#change_marker(<line1>, <line2>, <f-args>, 'i')
command! -buffer -nargs=1 VimwikiChangeSymbolInListTo
      \ call vimwiki#lst#change_marker_in_list(<f-args>)
command! -buffer -range VimwikiToggleListItem call vimwiki#lst#toggle_cb(<line1>, <line2>)
command! -buffer -range VimwikiToggleRejectedListItem
      \ call vimwiki#lst#toggle_rejected_cb(<line1>, <line2>)
command! -buffer -range VimwikiIncrementListItem call vimwiki#lst#increment_cb(<line1>, <line2>)
command! -buffer -range VimwikiDecrementListItem call vimwiki#lst#decrement_cb(<line1>, <line2>)
command! -buffer -range -nargs=+ VimwikiListChangeLvl
      \ call vimwiki#lst#change_level(<line1>, <line2>, <f-args>)
command! -buffer -range VimwikiRemoveSingleCB call vimwiki#lst#remove_cb(<line1>, <line2>)
command! -buffer VimwikiRemoveCBInList call vimwiki#lst#remove_cb_in_list()
command! -buffer VimwikiRenumberList call vimwiki#lst#adjust_numbered_list()
command! -buffer VimwikiRenumberAllLists call vimwiki#lst#adjust_whole_buffer()
command! -buffer VimwikiListToggle call vimwiki#lst#toggle_list_item()
command! -buffer -range VimwikiRemoveDone call vimwiki#lst#remove_done(1, "<range>", <line1>, <line2>)

" table commands
command! -buffer -nargs=* VimwikiTable call vimwiki#tbl#create(<f-args>)
command! -buffer -nargs=? VimwikiTableAlignQ call vimwiki#tbl#align_or_cmd('gqq', <f-args>)
command! -buffer -nargs=? VimwikiTableAlignW call vimwiki#tbl#align_or_cmd('gww', <f-args>)
command! -buffer VimwikiTableMoveColumnLeft call vimwiki#tbl#move_column_left()
command! -buffer VimwikiTableMoveColumnRight call vimwiki#tbl#move_column_right()

" diary commands
command! -buffer VimwikiDiaryNextDay call vimwiki#diary#goto_next_day()
command! -buffer VimwikiDiaryPrevDay call vimwiki#diary#goto_prev_day()

" tags commands
command! -buffer -bang VimwikiRebuildTags call vimwiki#tags#update_tags(1, '<bang>')
command! -buffer -nargs=* -complete=custom,vimwiki#tags#complete_tags
      \ VimwikiSearchTags call vimwiki#tags#search_tags(<q-args>)
command! -buffer -nargs=* -complete=custom,vimwiki#tags#complete_tags
      \ VimwikiGenerateTagLinks call vimwiki#tags#generate_tags(1, <f-args>)
command! -buffer -nargs=* -complete=custom,vimwiki#tags#complete_tags
      \ VimwikiGenerateTags
      \ call vimwiki#u#deprecate("VimwikiGenerateTags", "VimwikiGenerateTagLinks") |
      \ call vimwiki#tags#generate_tags(1, <f-args>)

command! -buffer VimwikiPasteUrl call vimwiki#html#PasteUrl(expand('%:p'))
command! -buffer VimwikiPasteLink call vimwiki#path#PasteLink(expand('%:p'))
command! -buffer VimwikiCatUrl call vimwiki#html#CatUrl(expand('%:p'))
command! -buffer -nargs=* -range -complete=custom,vimwiki#base#complete_colorize
      \ VimwikiColorize <line1>,<line2>call vimwiki#base#colorize(<f-args>)

" ------------------------------------------------
" Keybindings
" ------------------------------------------------

" mouse mappings
if str2nr(vimwiki#vars#get_global('key_mappings').mouse)
  nmap <buffer> <S-LeftMouse> <NOP>
  nmap <buffer> <C-LeftMouse> <NOP>
  nnoremap <silent><buffer> <2-LeftMouse>
        \ :call vimwiki#base#follow_link('nosplit', 0, 1, "\<lt>2-LeftMouse>")<CR>
  nnoremap <silent><buffer> <S-2-LeftMouse> <LeftMouse>:VimwikiSplitLink<CR>
  nnoremap <silent><buffer> <C-2-LeftMouse> <LeftMouse>:VimwikiVSplitLink<CR>
  nnoremap <silent><buffer> <MiddleMouse> <LeftMouse>:VimwikiBaddLink<CR>
  nnoremap <silent><buffer> <RightMouse><LeftMouse> :VimwikiGoBackLink<CR>
endif

" <Plug> HTML definitions
nnoremap <script><buffer> <Plug>Vimwiki2HTML :Vimwiki2HTML<CR>
nnoremap <script><buffer> <Plug>Vimwiki2HTMLBrowse :Vimwiki2HTMLBrowse<CR>

" default HTML key mappings
if str2nr(vimwiki#vars#get_global('key_mappings').html)
  call vimwiki#u#map_key('n', vimwiki#vars#get_global('map_prefix').'h', '<Plug>Vimwiki2HTML')
  call vimwiki#u#map_key('n', vimwiki#vars#get_global('map_prefix').'hh', '<Plug>Vimwiki2HTMLBrowse')
endif

" <Plug> links definitions
nnoremap <silent><script><buffer> <Plug>VimwikiFollowLink
    \ :VimwikiFollowLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiSplitLink
    \ :VimwikiSplitLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiVSplitLink
    \ :VimwikiVSplitLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiBaddLink
    \ :VimwikiBaddLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiNormalizeLink
    \ :VimwikiNormalizeLink 0<CR>
vnoremap <silent><script><buffer> <Plug>VimwikiNormalizeLinkVisual
    \ :<C-U>VimwikiNormalizeLink 1<CR>
vnoremap <silent><script><buffer> <Plug>VimwikiNormalizeLinkVisualCR
    \ :<C-U>VimwikiNormalizeLink 1<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiTabnewLink
    \ :VimwikiTabnewLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiTabDropLink
    \ :VimwikiTabDropLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiGoBackLink
    \ :VimwikiGoBackLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiNextLink
    \ :VimwikiNextLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiPrevLink
    \ :VimwikiPrevLink<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiGoto
    \ :VimwikiGoto<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiDeleteFile
    \ :VimwikiDeleteFile<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiRenameFile
    \ :VimwikiRenameFile<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiDiaryNextDay
    \ :VimwikiDiaryNextDay<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiDiaryPrevDay
    \ :VimwikiDiaryPrevDay<CR>
noremap <script><buffer> <Plug>VimwikiColorizeNormal
    \ :call vimwiki#base#colorize(vimwiki#base#get_user_color(), '')<CR>
vnoremap <script><buffer> <Plug>VimwikiColorize
    \ :call vimwiki#base#colorize(vimwiki#base#get_user_color(), visualmode())<CR>

" Declare Map: default links key mappings
if str2nr(vimwiki#vars#get_global('key_mappings').links)
  call vimwiki#u#map_key('n', '<CR>', '<Plug>VimwikiFollowLink')
  call vimwiki#u#map_key('n', '<S-CR>', '<Plug>VimwikiSplitLink')
  call vimwiki#u#map_key('n', '<C-CR>', '<Plug>VimwikiVSplitLink')
  call vimwiki#u#map_key('n', '<M-CR>', '<Plug>VimwikiBaddLink')
  call vimwiki#u#map_key('n', '+', '<Plug>VimwikiNormalizeLink')
  call vimwiki#u#map_key('v', '+', '<Plug>VimwikiNormalizeLinkVisual')
  call vimwiki#u#map_key('v', '<CR>', '<Plug>VimwikiNormalizeLinkVisualCR')
  call vimwiki#u#map_key('n', '<D-CR>', '<Plug>VimwikiTabDropLink')
  call vimwiki#u#map_key('n', '<C-S-CR>', '<Plug>VimwikiTabDropLink', 1)
  call vimwiki#u#map_key('n', '<BS>', '<Plug>VimwikiGoBackLink')
  call vimwiki#u#map_key('n', '<TAB>', '<Plug>VimwikiNextLink')
  call vimwiki#u#map_key('n', '<S-TAB>', '<Plug>VimwikiPrevLink')
  call vimwiki#u#map_key('n', vimwiki#vars#get_global('map_prefix').'n', '<Plug>VimwikiGoto')
  call vimwiki#u#map_key('n', vimwiki#vars#get_global('map_prefix').'d', '<Plug>VimwikiDeleteFile')
  call vimwiki#u#map_key('n', vimwiki#vars#get_global('map_prefix').'r', '<Plug>VimwikiRenameFile')
  call vimwiki#u#map_key('n', vimwiki#vars#get_global('map_prefix').'c', '<Plug>VimwikiColorizeNormal')
  call vimwiki#u#map_key('v', vimwiki#vars#get_global('map_prefix').'c', '<Plug>VimwikiColorize')
  call vimwiki#u#map_key('n', '<C-Down>', '<Plug>VimwikiDiaryNextDay')
  call vimwiki#u#map_key('n', '<C-Up>', '<Plug>VimwikiDiaryPrevDay')
endif

" Map: <Plug> lists definitions
nnoremap <silent><script><buffer> <Plug>VimwikiNextTask
    \ :VimwikiNextTask<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiToggleListItem
    \ :VimwikiToggleListItem<CR>
vnoremap <silent><script><buffer> <Plug>VimwikiToggleListItem
    \ :VimwikiToggleListItem<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiToggleRejectedListItem
    \ :VimwikiToggleRejectedListItem<CR>
vnoremap <silent><script><buffer> <Plug>VimwikiToggleRejectedListItem
    \ :VimwikiToggleRejectedListItem<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiIncrementListItem
    \ :VimwikiIncrementListItem<CR>
vnoremap <silent><script><buffer> <Plug>VimwikiIncrementListItem
    \ :VimwikiIncrementListItem<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiDecrementListItem
    \ :VimwikiDecrementListItem<CR>
vnoremap <silent><script><buffer> <Plug>VimwikiDecrementListItem
    \ :VimwikiDecrementListItem<CR>
inoremap <silent><script><buffer> <Plug>VimwikiDecreaseLvlSingleItem
    \ <C-O>:VimwikiListChangeLvl decrease 0<CR>
inoremap <silent><script><buffer> <Plug>VimwikiIncreaseLvlSingleItem
    \ <C-O>:VimwikiListChangeLvl increase 0<CR>
inoremap <silent><script><buffer> <Plug>VimwikiListNextSymbol
    \ <C-O>:VimwikiListChangeSymbolI next<CR>
inoremap <silent><script><buffer> <Plug>VimwikiListPrevSymbol
    \ <C-O>:VimwikiListChangeSymbolI prev<CR>
inoremap <silent><script><buffer> <Plug>VimwikiListToggle
    \ <Esc>:VimwikiListToggle<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiRenumberList
    \ :VimwikiRenumberList<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiRenumberAllLists
    \ :VimwikiRenumberAllLists<CR>
noremap <silent><script><buffer> <Plug>VimwikiDecreaseLvlSingleItem
    \ :VimwikiListChangeLvl decrease 0<CR>
noremap <silent><script><buffer> <Plug>VimwikiIncreaseLvlSingleItem
    \ :VimwikiListChangeLvl increase 0<CR>
noremap <silent><script><buffer> <Plug>VimwikiDecreaseLvlWholeItem
    \ :VimwikiListChangeLvl decrease 1<CR>
noremap <silent><script><buffer> <Plug>VimwikiIncreaseLvlWholeItem
    \ :VimwikiListChangeLvl increase 1<CR>
noremap <silent><script><buffer> <Plug>VimwikiRemoveSingleCB
    \ :VimwikiRemoveSingleCB<CR>
noremap <silent><script><buffer> <Plug>VimwikiRemoveCBInList
    \ :VimwikiRemoveCBInList<CR>
nnoremap <silent><buffer> <Plug>VimwikiListo
    \ :<C-U>call vimwiki#u#count_exe('call vimwiki#lst#kbd_o()')<CR>
nnoremap <silent><buffer> <Plug>VimwikiListO
    \ :<C-U>call vimwiki#u#count_exe('call vimwiki#lst#kbd_O()')<CR>

" Declare Map: default lists key mappings (again)
if str2nr(vimwiki#vars#get_global('key_mappings').lists)
  call vimwiki#u#map_key('n', 'gnt', '<Plug>VimwikiNextTask')
  if !hasmapto('<Plug>VimwikiToggleListItem')
    call vimwiki#u#map_key('n', '<C-Space>', '<Plug>VimwikiToggleListItem')
    call vimwiki#u#map_key('v', '<C-Space>', '<Plug>VimwikiToggleListItem', 1)
    if has('unix')
      call vimwiki#u#map_key('n', '<C-@>', '<Plug>VimwikiToggleListItem', 1)
      call vimwiki#u#map_key('v', '<C-@>', '<Plug>VimwikiToggleListItem', 1)
    endif
  endif
  call vimwiki#u#map_key('n', 'glx', '<Plug>VimwikiToggleRejectedListItem')
  call vimwiki#u#map_key('v', 'glx', '<Plug>VimwikiToggleRejectedListItem', 1)
  call vimwiki#u#map_key('n', 'gln', '<Plug>VimwikiIncrementListItem')
  call vimwiki#u#map_key('v', 'gln', '<Plug>VimwikiIncrementListItem', 1)
  call vimwiki#u#map_key('n', 'glp', '<Plug>VimwikiDecrementListItem')
  call vimwiki#u#map_key('v', 'glp', '<Plug>VimwikiDecrementListItem', 1)
  call vimwiki#u#map_key('i', '<C-D>', '<Plug>VimwikiDecreaseLvlSingleItem')
  call vimwiki#u#map_key('i', '<C-T>', '<Plug>VimwikiIncreaseLvlSingleItem')
  call vimwiki#u#map_key('n', 'glh', '<Plug>VimwikiDecreaseLvlSingleItem', 1)
  call vimwiki#u#map_key('n', 'gll', '<Plug>VimwikiIncreaseLvlSingleItem', 1)
  call vimwiki#u#map_key('n', 'gLh', '<Plug>VimwikiDecreaseLvlWholeItem')
  call vimwiki#u#map_key('n', 'gLH', '<Plug>VimwikiDecreaseLvlWholeItem', 1)
  call vimwiki#u#map_key('n', 'gLl', '<Plug>VimwikiIncreaseLvlWholeItem')
  call vimwiki#u#map_key('n', 'gLL', '<Plug>VimwikiIncreaseLvlWholeItem', 1)
  call vimwiki#u#map_key('i', '<C-L><C-J>', '<Plug>VimwikiListNextSymbol')
  call vimwiki#u#map_key('i', '<C-L><C-K>', '<Plug>VimwikiListPrevSymbol')
  call vimwiki#u#map_key('i', '<C-L><C-M>', '<Plug>VimwikiListToggle')
  call vimwiki#u#map_key('n', 'glr', '<Plug>VimwikiRenumberList')
  call vimwiki#u#map_key('n', 'gLr', '<Plug>VimwikiRenumberAllLists')
  call vimwiki#u#map_key('n', 'gLR', '<Plug>VimwikiRenumberAllLists', 1)
  call vimwiki#u#map_key('n', 'gl', '<Plug>VimwikiRemoveSingleCB')
  call vimwiki#u#map_key('n', 'gL', '<Plug>VimwikiRemoveCBInList')
  call vimwiki#u#map_key('n', 'o', '<Plug>VimwikiListo')
  call vimwiki#u#map_key('n', 'O', '<Plug>VimwikiListO')

  " Set lists_return to 0, if you don't want <CR> mapped to VimwikiReturn
  if str2nr(vimwiki#vars#get_global('key_mappings').lists_return)
    " Handle case of existing VimwikiReturn mappings outside the <Plug> definition
    " Note: Avoid interfering with popup/completion menu if it's active (#813)
    if maparg('<CR>', 'i') !~# '.*VimwikiReturn*.'
      if has('patch-7.3.489')
        " expand iabbrev on enter
        inoremap <expr><silent><buffer> <CR> pumvisible() ? '<CR>' : '<C-]><Esc>:VimwikiReturn 1 5<CR>'
      else
        inoremap <expr><silent><buffer> <CR> pumvisible() ? '<CR>' : '<Esc>:VimwikiReturn 1 5<CR>'
      endif
    endif
    if  maparg('<S-CR>', 'i') !~# '.*VimwikiReturn*.'
      inoremap <expr><silent><buffer> <S-CR> pumvisible() ? '<CR>' : '<Esc>:VimwikiReturn 2 2<CR>'
    endif
  endif

  " change symbol for bulleted lists
  for s:char in vimwiki#vars#get_syntaxlocal('bullet_types')
    if !hasmapto(':VimwikiChangeSymbolTo '.s:char.'<CR>')
      exe 'noremap <silent><buffer> gl'.s:char.' :VimwikiChangeSymbolTo '.s:char.'<CR>'
    endif
    if !hasmapto(':VimwikiChangeSymbolInListTo '.s:char.'<CR>')
      exe 'noremap <silent><buffer> gL'.s:char.' :VimwikiChangeSymbolInListTo '.s:char.'<CR>'
    endif
  endfor

  " change symbol for numbered lists
  for s:typ in vimwiki#vars#get_syntaxlocal('number_types')
    if !hasmapto(':VimwikiChangeSymbolTo '.s:typ.'<CR>')
      exe 'noremap <silent><buffer> gl'.s:typ[0].' :VimwikiChangeSymbolTo '.s:typ.'<CR>'
    endif
    if !hasmapto(':VimwikiChangeSymbolInListTo '.s:typ.'<CR>')
      exe 'noremap <silent><buffer> gL'.s:typ[0].' :VimwikiChangeSymbolInListTo '.s:typ.'<CR>'
    endif
  endfor

  " insert items in a list using langmap characters (see :h langmap)
  if !empty(&langmap)
    " Valid only if langmap is a comma separated pairs of chars
    let s:l_o = matchstr(&langmap, '\C,\zs.\zeo,')
    if s:l_o
      exe 'nnoremap <silent><buffer> '.s:l_o.' :call vimwiki#lst#kbd_o()<CR>a'
    endif

    let s:l_O = matchstr(&langmap, '\C,\zs.\zeO,')
    if s:l_O
      exe 'nnoremap <silent><buffer> '.s:l_O.' :call vimwiki#lst#kbd_O()<CR>a'
    endif
  endif
endif

function! s:CR(normal, just_mrkr) abort
  let res = vimwiki#tbl#kbd_cr()
  if res !=? ''
    exe 'normal! ' . res . "\<Right>"
    startinsert
    return
  endif
  call vimwiki#lst#kbd_cr(a:normal, a:just_mrkr)
endfunction

" insert mode table mappings
inoremap <silent><buffer><expr> <Plug>VimwikiTableNextCell
    \ vimwiki#tbl#kbd_tab()
inoremap <silent><buffer><expr> <Plug>VimwikiTablePrevCell
    \ vimwiki#tbl#kbd_shift_tab()
if str2nr(vimwiki#vars#get_global('key_mappings').table_mappings)
  call vimwiki#u#map_key('i', '<Tab>', '<Plug>VimwikiTableNextCell')
  call vimwiki#u#map_key('i', '<S-Tab>', '<Plug>VimwikiTablePrevCell')
endif

" <Plug> table formatting definitions
nnoremap <silent><buffer> <Plug>VimwikiTableAlignQ
    \ :VimwikiTableAlignQ<CR>
nnoremap <silent><buffer> <Plug>VimwikiTableAlignQ1
    \ :VimwikiTableAlignQ 2<CR>
nnoremap <silent><buffer> <Plug>VimwikiTableAlignW
    \ :VimwikiTableAlignW<CR>
nnoremap <silent><buffer> <Plug>VimwikiTableAlignW1
    \ :VimwikiTableAlignW 2<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiTableMoveColumnLeft
    \ :VimwikiTableMoveColumnLeft<CR>
nnoremap <silent><script><buffer> <Plug>VimwikiTableMoveColumnRight
    \ :VimwikiTableMoveColumnRight<CR>

" default table formatting key mappings
if str2nr(vimwiki#vars#get_global('key_mappings').table_format)
  call vimwiki#u#map_key('n', 'gqq', '<Plug>VimwikiTableAlignQ')
  call vimwiki#u#map_key('n', 'gq1', '<Plug>VimwikiTableAlignQ1')
  call vimwiki#u#map_key('n', 'gww', '<Plug>VimwikiTableAlignW')
  call vimwiki#u#map_key('n', 'gw1', '<Plug>VimwikiTableAlignW1')
  call vimwiki#u#map_key('n', '<A-Left>', '<Plug>VimwikiTableMoveColumnLeft')
  call vimwiki#u#map_key('n', '<A-Right>', '<Plug>VimwikiTableMoveColumnRight')
endif

" <Plug> text object definitions
onoremap <silent><buffer> <Plug>VimwikiTextObjHeader
    \ :<C-U>call vimwiki#base#TO_header(0, 0, v:count1)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjHeaderV
    \ :<C-U>call vimwiki#base#TO_header(0, 0, v:count1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjHeaderContent
    \ :<C-U>call vimwiki#base#TO_header(1, 0, v:count1)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjHeaderContentV
    \ :<C-U>call vimwiki#base#TO_header(1, 0, v:count1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjHeaderSub
    \ :<C-U>call vimwiki#base#TO_header(0, 1, v:count1)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjHeaderSubV
    \ :<C-U>call vimwiki#base#TO_header(0, 1, v:count1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjHeaderSubContent
    \ :<C-U>call vimwiki#base#TO_header(1, 1, v:count1)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjHeaderSubContentV
    \ :<C-U>call vimwiki#base#TO_header(1, 1, v:count1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjTableCell
    \ :<C-U>call vimwiki#base#TO_table_cell(0, 0)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjTableCellV
    \ :<C-U>call vimwiki#base#TO_table_cell(0, 1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjTableCellInner
    \ :<C-U>call vimwiki#base#TO_table_cell(1, 0)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjTableCellInnerV
    \ :<C-U>call vimwiki#base#TO_table_cell(1, 1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjColumn
    \ :<C-U>call vimwiki#base#TO_table_col(0, 0)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjColumnV
    \ :<C-U>call vimwiki#base#TO_table_col(0, 1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjColumnInner
    \ :<C-U>call vimwiki#base#TO_table_col(1, 0)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjColumnInnerV
    \ :<C-U>call vimwiki#base#TO_table_col(1, 1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjListChildren
    \ :<C-U>call vimwiki#lst#TO_list_item(0, 0)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjListChildrenV
    \ :<C-U>call vimwiki#lst#TO_list_item(0, 1)<CR>
onoremap <silent><buffer> <Plug>VimwikiTextObjListSingle
    \ :<C-U>call vimwiki#lst#TO_list_item(1, 0)<CR>
vnoremap <silent><buffer> <Plug>VimwikiTextObjListSingleV
    \ :<C-U>call vimwiki#lst#TO_list_item(1, 1)<CR>

" Declare Map: default text object key mappings
if str2nr(vimwiki#vars#get_global('key_mappings').text_objs)
  call vimwiki#u#map_key('o', 'ah', '<Plug>VimwikiTextObjHeader')
  call vimwiki#u#map_key('v', 'ah', '<Plug>VimwikiTextObjHeaderV')
  call vimwiki#u#map_key('o', 'ih', '<Plug>VimwikiTextObjHeaderContent')
  call vimwiki#u#map_key('v', 'ih', '<Plug>VimwikiTextObjHeaderContentV')
  call vimwiki#u#map_key('o', 'aH', '<Plug>VimwikiTextObjHeaderSub')
  call vimwiki#u#map_key('v', 'aH', '<Plug>VimwikiTextObjHeaderSubV')
  call vimwiki#u#map_key('o', 'iH', '<Plug>VimwikiTextObjHeaderSubContent')
  call vimwiki#u#map_key('v', 'iH', '<Plug>VimwikiTextObjHeaderSubContentV')
  call vimwiki#u#map_key('o', 'a\', '<Plug>VimwikiTextObjTableCell')
  call vimwiki#u#map_key('v', 'a\', '<Plug>VimwikiTextObjTableCellV')
  call vimwiki#u#map_key('o', 'i\', '<Plug>VimwikiTextObjTableCellInner')
  call vimwiki#u#map_key('v', 'i\', '<Plug>VimwikiTextObjTableCellInnerV')
  call vimwiki#u#map_key('o', 'ac', '<Plug>VimwikiTextObjColumn')
  call vimwiki#u#map_key('v', 'ac', '<Plug>VimwikiTextObjColumnV')
  call vimwiki#u#map_key('o', 'ic', '<Plug>VimwikiTextObjColumnInner')
  call vimwiki#u#map_key('v', 'ic', '<Plug>VimwikiTextObjColumnInnerV')
  call vimwiki#u#map_key('o', 'al', '<Plug>VimwikiTextObjListChildren')
  call vimwiki#u#map_key('v', 'al', '<Plug>VimwikiTextObjListChildrenV')
  call vimwiki#u#map_key('o', 'il', '<Plug>VimwikiTextObjListSingle')
  call vimwiki#u#map_key('v', 'il', '<Plug>VimwikiTextObjListSingleV')
endif

" Map: <Plug> header definitions
nnoremap <silent><buffer> <Plug>VimwikiAddHeaderLevel
      \ :<C-U>call vimwiki#base#AddHeaderLevel(v:count)<CR>
nnoremap <silent><buffer> <Plug>VimwikiRemoveHeaderLevel
      \ :<C-U>call vimwiki#base#RemoveHeaderLevel(v:count)<CR>
nnoremap <silent><buffer> <Plug>VimwikiGoToParentHeader
      \ :<C-u>call vimwiki#base#goto_parent_header()<CR>
nnoremap <silent><buffer> <Plug>VimwikiGoToNextHeader
      \ :<C-u>call vimwiki#base#goto_next_header()<CR>
nnoremap <silent><buffer> <Plug>VimwikiGoToPrevHeader
      \ :<C-u>call vimwiki#base#goto_prev_header()<CR>
nnoremap <silent><buffer> <Plug>VimwikiGoToNextSiblingHeader
      \ :<C-u>call vimwiki#base#goto_sibling(+1)<CR>
nnoremap <silent><buffer> <Plug>VimwikiGoToPrevSiblingHeader
      \ :<C-u>call vimwiki#base#goto_sibling(-1)<CR>

" Declare Map Header: default header key mappings
if str2nr(vimwiki#vars#get_global('key_mappings').headers)
  call vimwiki#u#map_key('n', '=', '<Plug>VimwikiAddHeaderLevel')
  call vimwiki#u#map_key('n', '-', '<Plug>VimwikiRemoveHeaderLevel')
  call vimwiki#u#map_key('n', ']u', '<Plug>VimwikiGoToParentHeader')
  call vimwiki#u#map_key('n', '[u', '<Plug>VimwikiGoToParentHeader', 1)
  call vimwiki#u#map_key('n', ']]', '<Plug>VimwikiGoToNextHeader')
  call vimwiki#u#map_key('n', '[[', '<Plug>VimwikiGoToPrevHeader')
  call vimwiki#u#map_key('n', ']=', '<Plug>VimwikiGoToNextSiblingHeader')
  call vimwiki#u#map_key('n', '[=', '<Plug>VimwikiGoToPrevSiblingHeader')
endif

if vimwiki#vars#get_wikilocal('auto_export')
  " Automatically generate HTML on page write.
  augroup vimwiki
    au BufWritePost <buffer>
      \ call vimwiki#html#Wiki2HTML(expand(vimwiki#vars#get_wikilocal('path_html')),
      \                             expand('%'))
  augroup END
endif

if vimwiki#vars#get_wikilocal('auto_toc')
  " Automatically update the TOC *before* the file is written
  augroup vimwiki
    au BufWritePre <buffer> call vimwiki#base#table_of_contents(0)
  augroup END
endif

if vimwiki#vars#get_wikilocal('auto_tags')
  " Automatically update tags metadata on page write.
  augroup vimwiki
    au BufWritePre <buffer> call vimwiki#tags#update_tags(0, '')
  augroup END
endif

nnoremap <buffer> <F5> :Vimwiki2HTMLBrowse<CR>

" Insert vimwiki links to include the clipboard images.
function! InsertImages()
  let home = substitute(g:home,'\','/','g').'/HOME'
  let fname = strftime('%Y%m%d_%H%M%S').'.png'
  let full_fname = home . '/wiki_images/'. fname
  if  expand('%') =~# 'diary'
    let @c = '{{local:../../wiki_images/'.fname.'}}'
  else
    let @c = '{{local:../wiki_images/'.fname.'}}'
  endif
  let @e = 'ERROR'
  let cmd = 'python '.g:home.'/sites/vimwiki/ftplugin/saveClipBoard.py '.full_fname
  let out = system(cmd)
  if out =~# 'OK'
    put c
  else
    let @e = cmd.':'.out
    put e
  endif
endfunction
nnoremap <silent> <buffer> <Leader>wm :call InsertImages()<CR>
nmap <silent><buffer> <F3> <Plug>VimwikiToggleListItem
if vimwiki#vars#get_wikilocal('auto_generate_links')
  " Automatically generate links *before* the file is written
  augroup vimwiki
    au BufWritePre <buffer> call vimwiki#base#generate_links(0)
  augroup END
endif

if vimwiki#vars#get_wikilocal('auto_generate_tags')
  " Automatically generate tags *before* the file is written
  augroup vimwiki
    au BufWritePre <buffer> call vimwiki#tags#generate_tags(0)
  augroup END
endif
