vim9script

set nocompatible nomore
set cmdheight=20
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

# Search options are user interface state, not parser configuration.  C-style
# markers contain `*`, and blank/indent patterns contain `*` as a quantifier;
# both used to change meaning under 'nomagic'.
set nomagic
setline(1, ['one', '  two', ''])
setlocal commentstring=/*\ %s\ */
simplecomment#Toggle(1, 3)
assert_equal(['/* one */', '  /* two */', ''], getline(1, 3))
simplecomment#Toggle(1, 3)
assert_equal(['one', '  two', ''], getline(1, 3))
set magic

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

# A dotted 'filetype' is the first component only: html.mustache is HTML, not a
# made-up language, so the buffer's commentstring keeps winning.
setlocal filetype=python.django commentstring=#\ %s
setline(1, ['print(1)'])
deletebufline('%', 2, '$')
simplecomment#Toggle(1, 1)
assert_equal('# print(1)', getline(1),
  'a dotted filetype did not use the buffer commentstring')
simplecomment#Toggle(1, 1)
assert_equal('print(1)', getline(1))

# Ranges that invert or sit outside the buffer must not throw and must not
# invent a line to comment.
setline(1, ['keep'])
deletebufline('%', 2, '$')
simplecomment#Toggle(0, 0)
assert_equal(['keep'], getline(1, 1))
simplecomment#Toggle(-3, 1)
assert_equal(['# keep'], getline(1, 1))

# Unwritable buffers warn and leave the text alone; Health must agree instead
# of reporting "writable" because 'modifiable' is still set.
setline(1, ['keep'])
setlocal readonly
try
  silent simplecomment#Toggle(1, 1)
catch
  assert_report('a readonly buffer threw: ' .. v:exception)
endtry
assert_equal('keep', getline(1), 'a readonly buffer was edited')
setlocal noreadonly
setlocal nomodifiable
try
  silent simplecomment#Toggle(1, 1)
catch
  assert_report('a nomodifiable buffer threw: ' .. v:exception)
endtry
assert_equal('keep', getline(1), 'a nomodifiable buffer was edited')
setlocal modifiable

# Unusable commentstring values are a no-op, not an operator exception, and
# Health names the gap instead of printing an empty marker.
&l:commentstring = ''
try
  silent simplecomment#Toggle(1, 1)
catch
  assert_report('an empty commentstring threw: ' .. v:exception)
endtry
assert_equal('keep', getline(1))
&l:commentstring = ' %s'
try
  silent simplecomment#Toggle(1, 1)
catch
  assert_report('a marker-less commentstring threw: ' .. v:exception)
endtry
assert_equal('keep', getline(1))
&l:commentstring = '%s '
try
  silent simplecomment#Toggle(1, 1)
catch
  assert_report('a suffix-only commentstring threw: ' .. v:exception)
endtry
assert_equal('keep', getline(1))
&l:commentstring = '# %s'

# Non-string table entries are skipped, not compared as markers.
g:simplecomment_commentstrings = {python: 3}
try
  simplecomment#Toggle(1, 1)
catch
  assert_report('a non-string commentstring table value threw: ' .. v:exception)
endtry
assert_equal('# keep', getline(1))
unlet g:simplecomment_commentstrings
simplecomment#Toggle(1, 1)
assert_equal('keep', getline(1))

# Toggle must put the cursor back: fence detection (and setline) used to be
# able to leave it on column 1 of another line.
setline(1, ['alpha()', '  beta()'])
cursor(2, 4)
simplecomment#Toggle(1, 2)
assert_equal([2, 4], [line('.'), col('.')],
  'Toggle moved the cursor while rewriting the range')
assert_equal(['# alpha()', '  # beta()'], getline(1, 2))
simplecomment#Toggle(1, 2)

assert_equal(2, exists(':SimpleCommentToggle'))
assert_match('simplecomment', maparg('<Plug>(simplecomment-toggle-line)', 'n'))

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
