vim9script

var s_operator_pending = false

def Warn(message: string)
  echohl WarningMsg
  echomsg '[SimpleComment] ' .. message
  echohl None
enddef

def CommentParts(): dict<string>
  var format = &l:commentstring
  var marker = match(format, '%s')
  if marker < 0
    return {}
  endif
  return {
    left: trim(strpart(format, 0, marker)),
    right: trim(strpart(format, marker + 2)),
  }
enddef

def Escape(text: string): string
  return escape(text, '\.^$~[]*')
enddef

def IsCommented(line: string, parts: dict<string>): bool
  if line =~# '^\s*$' || empty(parts.left)
    return line =~# '^\s*$'
  endif
  var body = substitute(line, '^\s*', '', '')
  if body !~# '^' .. Escape(parts.left) .. '\%($\|\s\)'
    return false
  endif
  if empty(parts.right)
    return true
  endif
  return body =~# Escape(parts.right) .. '\s*$'
enddef

def CommentLine(line: string, parts: dict<string>): string
  if line =~# '^\s*$'
    return line
  endif
  var indent = matchstr(line, '^\s*')
  var body = strpart(line, strlen(indent))
  var left = parts.left .. (parts.left =~# '\s$' ? '' : ' ')
  var right = empty(parts.right) ? '' : (parts.right =~# '^\s' ? '' : ' ') .. parts.right
  return indent .. left .. body .. right
enddef

def UncommentLine(line: string, parts: dict<string>): string
  if line =~# '^\s*$'
    return line
  endif
  var indent = matchstr(line, '^\s*')
  var body = strpart(line, strlen(indent))
  body = substitute(body, '^' .. Escape(parts.left) .. '\s\?', '', '')
  if !empty(parts.right)
    body = substitute(body, '\s\?' .. Escape(parts.right) .. '\s*$', '', '')
  endif
  return indent .. body
enddef

export def Toggle(first: number, last: number)
  if !&l:modifiable || &l:readonly
    Warn('current buffer is not writable')
    return
  endif
  var parts = CommentParts()
  if empty(parts) || empty(parts.left)
    Warn($'no usable commentstring for filetype {&l:filetype}')
    return
  endif
  var start = max([1, first])
  var finish = min([line('$'), last])
  var lines = getline(start, finish)
  var nonblank = filter(copy(lines), (_, value) => value !~# '^\s*$')
  if empty(nonblank)
    return
  endif
  var remove = empty(filter(copy(nonblank), (_, value) => !IsCommented(value, parts)))
  var changed = mapnew(lines, (_, value) => remove
    ? UncommentLine(value, parts)
    : CommentLine(value, parts))
  var view = winsaveview()
  try
    setline(start, changed)
  finally
    winrestview(view)
  endtry
enddef

def OperatorApply(_type: string)
  s_operator_pending = false
  Toggle(line("'["), line("']"))
enddef

export def Operator()
  &operatorfunc = matchstr(expand('<SID>'), '<SNR>\d\+_') .. 'OperatorApply'
  s_operator_pending = true
  feedkeys('g@', 'n')
enddef

export def Visual()
  Toggle(line("'<"), line("'>"))
enddef

export def Health()
  echomsg 'SimpleComment health'
  echomsg $'  commentstring: {empty(&l:commentstring) ? "missing" : &l:commentstring}'
  echomsg $'  buffer: {&l:modifiable && !&l:readonly ? "writable" : "read-only"}'
  echomsg $'  operator: {s_operator_pending ? "pending" : "idle"}'
enddef
