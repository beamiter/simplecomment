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

# The scan that decides between commenting and uncommenting stops at the first
# line that is not commented yet, so a range that is only partly commented has
# to come out commented all through rather than half stripped.
setlocal commentstring=#\ %s
setline(1, ['# one', 'two', '# three'])
simplecomment#Toggle(1, 3)
assert_equal(['# # one', '# two', '# # three'], getline(1, 3))
simplecomment#Toggle(1, 3)
assert_equal(['# one', 'two', '# three'], getline(1, 3))

# A marker on its own is a commented line: the pattern has to accept end of
# line where it otherwise wants a space.
setline(1, ['#', '# two'])
simplecomment#Toggle(1, 2)
assert_equal(['', 'two'], getline(1, 2))

# Markers full of regex metacharacters survive being baked into the patterns
# once per range instead of once per line.
setlocal commentstring=--[[%s]]
setline(1, ["\tone", '  two'])
simplecomment#Toggle(1, 2)
assert_equal(["\t--[[ one ]]", '  --[[ two ]]'], getline(1, 2))
simplecomment#Toggle(1, 2)
assert_equal(["\tone", '  two'], getline(1, 2))

# An empty comment body must give the indent back untouched.  Taking the opener
# off first leaves `  <!-- -->` as `  -->`, and the closer's optional leading
# space then has nothing but indent within reach: the line came back one space
# short, and a tab-indented one lost the whole level.
setlocal commentstring=<!--%s-->
setline(1, ['  <!-- -->', "\t<!-- -->", '  <!-- x -->'])
simplecomment#Toggle(1, 3)
assert_equal(['  ', "\t", '  x'], getline(1, 3))

setlocal commentstring=/*%s*/
setline(1, ['    /* */'])
deletebufline('%', 2, '$')
simplecomment#Toggle(1, 1)
assert_equal(['    '], getline(1, 1))

# Ranges outside the buffer are clamped, and a range with nothing in it leaves
# the buffer alone.
setlocal commentstring=#\ %s
setline(1, ['one', ''])
deletebufline('%', 3, '$')
simplecomment#Toggle(1, 999)
assert_equal(['# one', ''], getline(1, 2))
simplecomment#Toggle(2, 2)
assert_equal(['# one', ''], getline(1, 2))
simplecomment#Toggle(2, 1)
assert_equal(['# one', ''], getline(1, 2))

assert_equal(2, exists(':SimpleCommentToggle'))
assert_match('simplecomment', maparg('<Plug>(simplecomment-toggle-line)', 'n'))

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
