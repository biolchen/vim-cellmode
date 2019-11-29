function! Unindent(code)
  let l:lines = split(a:code, "\n")
  if len(l:lines) == 0 " Special case for empty string
    return a:code
  end
  let l:nindents = strlen(matchstr(l:lines[0], '^\s*'))
  let l:subcmd = 'substitute(v:val, "^\\s\\{' . l:nindents . '\\}", "", "")'
  call map(l:lines, l:subcmd)
  let l:ucode = join(l:lines, "\n")
  return l:ucode
endfunction

function! GetVar(name, default)
  if (exists ("b:" . a:name))
    return b:{a:name}
  elseif (exists ("g:" . a:name))
    return g:{a:name}
  else
    return a:default
  end
endfunction

function! CleanupTempFiles()
  if (exists('b:cellmode_fnames'))
    for fname in b:cellmode_fnames
      call delete(fname)
    endfor
    unlet b:cellmode_fnames
  end
endfunction

function! GetNextTempFile()
  if !exists("b:cellmode_fnames")
    au BufDelete <buffer> call CleanupTempFiles()
    let b:cellmode_fnames = []
    for i in range(1, b:cellmode_n_files)
      call add(b:cellmode_fnames, tempname() . ".ipy")
    endfor
    let b:cellmode_fnames_index = 0
  end
  let l:cellmode_fname = b:cellmode_fnames[b:cellmode_fnames_index]
  if (b:cellmode_fnames_index >= b:cellmode_n_files - 1)
    let b:cellmode_fnames_index = 0
  else
    let b:cellmode_fnames_index += 1
  endif

  return l:cellmode_fname
endfunction

function! DefaultVars()
  let b:cellmode_n_files = GetVar('cellmode_n_files', 10)

  if !exists("b:cellmode_use_tmux")
    let b:cellmode_use_tmux = GetVar('cellmode_use_tmux', 1)
  end

  if !exists("b:cellmode_cell_delimiter")
    let b:cellmode_cell_delimiter = GetVar('cellmode_cell_delimiter',
                                         \ '\(##\|#%%\|#\s%%\)')
  end

  if !exists("b:cellmode_tmux_sessionname") ||
   \ !exists("b:cellmode_tmux_windowname") ||
   \ !exists("b:cellmode_tmux_panenumber")
    let b:cellmode_tmux_sessionname = GetVar('cellmode_tmux_sessionname', '')
    let b:cellmode_tmux_windowname = GetVar('cellmode_tmux_windowname', '')
    let b:cellmode_tmux_panenumber = GetVar('cellmode_tmux_panenumber', '0')
  end

  if !exists("g:cellmode_screen_sessionname") ||
   \ !exists("b:cellmode_screen_window")
    let b:cellmode_screen_sessionname = GetVar('cellmode_screen_sessionname', 'ipython')
    let b:cellmode_screen_window = GetVar('cellmode_screen_window', '0')
  end
endfunction

function! CallSystem(cmd)
  " Execute the given system command, reporting errors if any
  let l:out = system(a:cmd)
  if v:shell_error != 0
    echom 'Vim-cellmode, error running ' . a:cmd . ' : ' . l:out
  end
endfunction

function! CopyToTmux(code)
  let l:my_filetype = &filetype
  let l:lines = split(a:code, "\n")
  if len(l:lines) == 0
    call add(l:lines, ' ')
  end
  let l:cellmode_fname = GetNextTempFile()
  call writefile(l:lines, l:cellmode_fname)
  if strlen(b:cellmode_tmux_sessionname) == 0
    let l:sprefix = ''
  else
    let l:sprefix = '$'
  end
  let target = l:sprefix . b:cellmode_tmux_sessionname . ':'
             \ . b:cellmode_tmux_windowname . '.'
             \ . b:cellmode_tmux_panenumber

  if l:my_filetype ==# 'sh'
    call CallSystem("tmux set-buffer \"sh " . l:cellmode_fname . "\"")
  elseif l:my_filetype ==# 'javascript'
    call CallSystem("tmux set-buffer \".load " . l:cellmode_fname . "\"")
  elseif l:my_filetype ==# 'sql'
    call CallSystem("tmux set-buffer \"source " . l:cellmode_fname . "\"")
  elseif l:my_filetype ==# 'pandoc'
    call CallSystem("tmux set-buffer \"%load -y " . l:cellmode_fname . "\n\"")
  end
  call CallSystem('tmux paste-buffer -t "' . target . '"')
  let downlist = repeat('Down ', len(l:lines) + 1)
  call CallSystem('tmux send-keys -t "' . target . '" ' . downlist)
  call CallSystem('tmux send-keys -t "' . target . '" Enter')
endfunction

function! RunTmuxReg()
  let l:code = Unindent(@a)
  call CopyToTmux(l:code)
endfunction

function! RunTmuxCell(restore_cursor)
  call DefaultVars()
  if a:restore_cursor
    let l:winview = winsaveview()
  end

  let l:pat = ':?' . b:cellmode_cell_delimiter . '?;/' . b:cellmode_cell_delimiter . '/y a'

  silent exe l:pat
  execute "normal! ']"
  execute "normal! j"

  let @a=join(split(@a, "\n")[1:-2], "\n")
  call RunTmuxReg()
  if a:restore_cursor
    call winrestview(l:winview)
  end
endfunction

function! RunTmuxChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  call RunTmuxReg()
endfunction

function! RunTmuxLine()
  call DefaultVars()
  " Yank current selection to register a
  silent normal "ayy
  call RunTmuxReg()
endfunction

function! InitVariable(var, value)
    if !exists(a:var)
        execute 'let ' . a:var . ' = ' . "'" . a:value . "'"
        return 1
    endif
    return 0
endfunction

call InitVariable("g:cellmode_default_mappings", 1)

if g:cellmode_default_mappings
    vmap <silent> <C-c> :call RunTmuxChunk()<CR>
    noremap <silent> <C-b> :call RunTmuxCell(0)<CR>
    noremap <silent> <C-g> :call RunTmuxCell(1)<CR>
endif
