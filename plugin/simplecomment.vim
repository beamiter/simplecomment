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

if g:simplecomment_default_mappings
  nmap gc <Plug>(simplecomment-operator)
  nmap gcc <Plug>(simplecomment-toggle-line)
  xmap gc <Plug>(simplecomment-toggle)
endif
