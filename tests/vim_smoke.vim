vim9script

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplecomment.vim')

new
setlocal filetype=python commentstring=#\ %s
setline(1, ['alpha()', '  beta()', '', '# gamma()'])
simplecomment#Toggle(1, 2)
assert_equal(['# alpha()', '  # beta()', '', '# gamma()'], getline(1, 4))
simplecomment#Toggle(1, 4)
assert_equal(['alpha()', '  beta()', '', 'gamma()'], getline(1, 4))

setlocal commentstring=/*%s*/
setline(1, ['one', '  two'])
simplecomment#Toggle(1, 2)
assert_equal(['/* one */', '  /* two */'], getline(1, 2))
simplecomment#Toggle(1, 2)
assert_equal(['one', '  two'], getline(1, 2))

assert_equal(2, exists(':SimpleCommentToggle'))
assert_match('simplecomment', maparg('<Plug>(simplecomment-toggle-line)', 'n'))

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
