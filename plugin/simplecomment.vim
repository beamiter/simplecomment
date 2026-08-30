vim9script

if exists('g:loaded_simplecomment')
  finish
endif
g:loaded_simplecomment = 1

if v:version < 901
  echohl WarningMsg
  echomsg '[SimpleComment] Vim 9.1 or newer is required.'
  echohl None
  finish
endif

g:simplecomment_default_mappings = get(g:, 'simplecomment_default_mappings', 1)

command! -range SimpleCommentToggle simplecomment#Toggle(<line1>, <line2>)
command! SimpleCommentHealth simplecomment#Health()

nnoremap <silent> <Plug>(simplecomment-toggle-line) <ScriptCmd>simplecomment#Toggle(line('.'), line('.'))<CR>
nnoremap <silent> <Plug>(simplecomment-operator) <ScriptCmd>simplecomment#Operator()<CR>
xnoremap <silent> <Plug>(simplecomment-toggle) <ScriptCmd>simplecomment#Visual()<CR>

# Defaults never replace a mapping owned by the user.  plugin/ files load after
# vimrc, so an unconditional `nmap gc` silently took over a `gc` the user had
# bound there -- and whether the plugin or the user won depended only on where
# the user had written their mapping, which is not a rule anyone can follow.
# maparg() answers "is this key still free"; hasmapto() answers "has the user
# already routed this <Plug> target somewhere of their own", in which case they
# do not also want the default key taken.
if g:simplecomment_default_mappings
  if maparg('gc', 'n') ==# '' && !hasmapto('<Plug>(simplecomment-operator)', 'n')
    nmap gc <Plug>(simplecomment-operator)
  endif
  if maparg('gcc', 'n') ==# '' && !hasmapto('<Plug>(simplecomment-toggle-line)', 'n')
    nmap gcc <Plug>(simplecomment-toggle-line)
  endif
  if maparg('gc', 'x') ==# '' && !hasmapto('<Plug>(simplecomment-toggle)', 'x')
    xmap gc <Plug>(simplecomment-toggle)
  endif
endif
