vim9script

# Regression tests for the region-aware commentstring.  Every case here was
# broken before: a line of JavaScript in a <script> block, a CSS rule in a
# <style> block and a line inside a ```rust fence all came out wrapped in
# <!-- -->, which compiles in none of the three languages.
#
# These need real filetype detection and a real syntax engine, so unlike
# vim_smoke.vim they load both from $VIMRUNTIME and edit fixture files.

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplecomment.vim')
filetype plugin indent on
syntax on

# 'commentstring' is pinned by hand after each edit so the assertions describe
# this plugin rather than whichever value this Vim's ftplugin happens to ship.
def Open(name: string, commentstring: string)
  silent execute 'edit! ' .. fnameescape(ROOT .. '/tests/fixtures/' .. name)
  &l:commentstring = commentstring
enddef

# --- JavaScript inside <script> -------------------------------------------

Open('embedded.html', '<!--%s-->')
assert_equal('html', &l:filetype)
simplecomment#Toggle(3, 4)
assert_equal(['    // let x = 1;', '    // let y = 2;'], getline(3, 4))
simplecomment#Toggle(3, 4)
assert_equal(['    let x = 1;', '    let y = 2;'], getline(3, 4))

# --- CSS inside <style> ----------------------------------------------------

Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(7, 7)
assert_equal('    /* .b { color: red; } */', getline(7))
simplecomment#Toggle(7, 7)
assert_equal('    .b { color: red; }', getline(7))

# --- the tags around them are still HTML -----------------------------------

Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(2, 2)
assert_equal('  <!-- <script> -->', getline(2))
simplecomment#Toggle(1, 1)
assert_equal('<!-- <div class="a"> -->', getline(1))

# --- a range that crosses a region boundary --------------------------------
#
# Giving each line the markers of its own region would produce
#
#     <!-- <script> -->
#     // let x = 1;
#     <!-- </script> -->
#
# where the JavaScript is no longer inside a script element and renders on the
# page as text.  A range that crosses a boundary is being edited as the
# enclosing language, so all of it gets the enclosing markers.

Open('embedded.html', '<!--%s-->')
const HTML_SOURCE = getline(1, 9)
simplecomment#Toggle(1, 9)
assert_equal([
  '<!-- <div class="a"> -->',
  '  <!-- <script> -->',
  '    <!-- let x = 1; -->',
  '    <!-- let y = 2; -->',
  '  <!-- </script> -->',
  '  <!-- <style> -->',
  '    <!-- .b { color: red; } -->',
  '  <!-- </style> -->',
  '<!-- </div> -->',
], getline(1, 9))
simplecomment#Toggle(1, 9)
assert_equal(HTML_SOURCE, getline(1, 9))

# --- one toggle is one undo ------------------------------------------------

Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(1, 9)
assert_notequal(HTML_SOURCE, getline(1, 9))
silent undo
assert_equal(HTML_SOURCE, getline(1, 9))

# The same for a range that used a detected region, which is written back by
# the same single setline().
Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(3, 4)
assert_equal(['    // let x = 1;', '    // let y = 2;'], getline(3, 4))
silent undo
assert_equal(['    let x = 1;', '    let y = 2;'], getline(3, 4))

# --- fenced code in Markdown -----------------------------------------------

Open('fenced.md', '<!--%s-->')
assert_equal('markdown', &l:filetype)
simplecomment#Toggle(4, 6)
assert_equal(['// fn main() { println!("hi"); }', '', '// let z = 3;'], getline(4, 6))
simplecomment#Toggle(4, 6)
assert_equal(['fn main() { println!("hi"); }', '', 'let z = 3;'], getline(4, 6))

# The fence line itself is Markdown: commenting it with Rust's markers would
# leave the fence half eaten.
Open('fenced.md', '<!--%s-->')
simplecomment#Toggle(3, 3)
assert_equal('<!-- ```rust -->', getline(3))
simplecomment#Toggle(7, 7)
assert_equal('<!-- ``` -->', getline(7))
# And a closing fence commented back out again: the comment destroyed the
# fence, so this line now looks like part of the block above it.  It still has
# to uncomment rather than pick up a second set of markers.
simplecomment#Toggle(7, 7)
assert_equal('```', getline(7))

# Prose is Markdown too.
Open('fenced.md', '<!--%s-->')
simplecomment#Toggle(1, 1)
assert_equal('<!-- Some prose here. -->', getline(1))

# A fence info string that is only a shorter spelling of a language we know.
Open('fenced.md', '<!--%s-->')
simplecomment#Toggle(18, 18)
assert_equal('// const q = 1;', getline(18))

# `c++` is the other spelling of cpp; the fence info string is what the syntax
# engine will never tell us, so the alias table has to.
Open('fenced.md', '<!--%s-->')
simplecomment#Toggle(24, 24)
assert_equal('// int y = 1;', getline(24),
  'a ```c++ fence did not use C++ markers')
simplecomment#Toggle(24, 24)
assert_equal('int y = 1;', getline(24))

# --- unknown context falls back, it never guesses --------------------------

# ```mermaid has no entry in the table, so the buffer's 'commentstring' is used
# rather than a marker made up for it.
Open('fenced.md', '<!--%s-->')
simplecomment#Toggle(10, 10)
assert_equal('<!-- graph TD; -->', getline(10))

# A fence that declares no language at all is just as unknown.
simplecomment#Toggle(14, 14)
assert_equal('<!-- plain fence body -->', getline(14))

# A range crossing the fence is the enclosing language, like the HTML one.
Open('fenced.md', '<!--%s-->')
simplecomment#Toggle(3, 7)
assert_equal([
  '<!-- ```rust -->',
  '<!-- fn main() { println!("hi"); } -->',
  '',
  '<!-- let z = 3; -->',
  '<!-- ``` -->',
], getline(3, 7))

# --- JSX -------------------------------------------------------------------

# Vim's own javascript syntax says nothing at all about JSX markup -- synstack()
# is empty on those lines -- so the buffer's 'commentstring' is used.  That is
# the wrong comment for a JSX child, but the syntax engine has not told us we
# are in one, and the fallback is the old behaviour rather than a guess.
Open('markup.jsx', '//%s')
assert_equal('javascriptreact', &l:filetype)
assert_equal([], synstack(3, 5))
simplecomment#Toggle(3, 3)
assert_equal('    // <span>hello</span>', getline(3))
simplecomment#Toggle(3, 3)
assert_equal('    <span>hello</span>', getline(3))

# With a syntax that does mark the markup -- jsxRegion is the group name the
# common JSX syntax plugins use -- the region is recognised and gets JSX's own
# comment form.  The region below is a stand-in for such a plugin: it claims
# both the markup and the {...} expression container a real one would, which is
# what lets the comment be taken off again.
Open('markup.jsx', '//%s')
syntax region jsxRegion start=+^\s*[<{]+ end=+$+ keepend
simplecomment#Toggle(3, 3)
assert_equal('    {/* <span>hello</span> */}', getline(3))
simplecomment#Toggle(3, 3)
assert_equal('    <span>hello</span>', getline(3))

# --- file type aliases -----------------------------------------------------

# javascriptreact is JavaScript, so a plain JavaScript line in it keeps the
# buffer's 'commentstring' instead of being overridden by the table entry.
g:simplecomment_commentstrings = {javascript: '/* %s */'}
Open('markup.jsx', '//%s')
simplecomment#Toggle(1, 1)
assert_equal('// const App = () => (', getline(1))

# ... while the same entry does decide a JavaScript region inside HTML.
Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(3, 3)
assert_equal('    /* let x = 1; */', getline(3))

# An entry set to an empty string puts that language back on the buffer's
# 'commentstring'.
g:simplecomment_commentstrings = {javascript: ''}
Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(3, 3)
assert_equal('    <!-- let x = 1; -->', getline(3))
unlet g:simplecomment_commentstrings

# --- a host that highlights its own code with another language's groups -----

# syntax/cpp.vim sources syntax/c.vim, so every line here is a cType or a
# cStatement and resolves to `c`.  That is not an embedded C region, it is C++,
# so the buffer's 'commentstring' still decides.  Reading the group name alone
# overruled a user who had set it to // by hand ...
Open('dialect.cpp', '// %s')
assert_equal('cpp', &l:filetype)
assert_equal('cType', synIDattr(synID(2, 3, 0), 'name'))
simplecomment#Toggle(2, 2)
assert_equal('  // int x = 1;', getline(2))
simplecomment#Toggle(2, 2)
assert_equal('  int x = 1;', getline(2))

# ... and it did worse than that on a line that already carried a block
# comment: `/* already */` looked like it was wearing our markers, so a `gc`
# meant to comment the line stripped the user's comment instead.
Open('dialect.cpp', '// %s')
simplecomment#Toggle(3, 3)
assert_equal('  // /* already */', getline(3))

# syntax/scss.vim sources syntax/css.vim the same way, and there it split one
# file in two: sassX named the selector line so it stayed //, cssTextProp named
# the property under it so that one turned into /* */.
Open('dialect.scss', '// %s')
assert_equal('scss', &l:filetype)
simplecomment#Toggle(1, 1)
assert_equal('// .a {', getline(1))
Open('dialect.scss', '// %s')
simplecomment#Toggle(2, 2)
assert_equal('  // color: red;', getline(2))
Open('dialect.scss', '// %s')
simplecomment#Toggle(3, 3)
assert_equal('// }', getline(3))

# The health report agrees: this is the buffer's own code, not a region.
Open('dialect.scss', '// %s')
cursor(2, 1)
assert_match('context: buffer (scss)', execute('SimpleCommentHealth'))

# --- the detection budget --------------------------------------------------

# Zero turns detection off, and then every range behaves exactly as it did
# before regions were detected at all.
g:simplecomment_context_lines = 0
Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(3, 3)
assert_equal('    <!-- let x = 1; -->', getline(3))
simplecomment#Toggle(3, 3)
assert_equal('    let x = 1;', getline(3))

# A range longer than the budget is over budget even when it would have been
# detected: the fallback is the whole point of the limit.
g:simplecomment_context_lines = 1
Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(3, 4)
assert_equal(['    <!-- let x = 1; -->', '    <!-- let y = 2; -->'], getline(3, 4))
unlet g:simplecomment_context_lines

# Runtime configuration is read on every toggle.  A typo must fall back to the
# defaults instead of throwing from an operator, and alias keys are normalized
# the same way fence/filetype names are.
g:simplecomment_context_lines = v:true
Open('embedded.html', '<!--%s-->')
try
  simplecomment#Toggle(3, 3)
catch
  assert_report('a bool context limit threw: ' .. v:exception)
endtry
assert_equal('    // let x = 1;', getline(3),
  'a bool context limit did not fall back to the numeric default')
unlet g:simplecomment_context_lines

g:simplecomment_commentstrings = {javascript: 'NOPE'}
Open('embedded.html', '<!--%s-->')
try
  simplecomment#Toggle(3, 3)
catch
  assert_report('an invalid commentstring override threw: ' .. v:exception)
endtry
assert_equal('    <!-- let x = 1; -->', getline(3),
  'a marker-less override must fall back to commentstring, not emit NOPE')
unlet g:simplecomment_commentstrings

g:simplecomment_context_lines = 'many'
Open('embedded.html', '<!--%s-->')
try
  simplecomment#Toggle(3, 3)
catch
  assert_report('a mistyped context limit threw: ' .. v:exception)
endtry
assert_equal('    // let x = 1;', getline(3))
unlet g:simplecomment_context_lines

g:simplecomment_commentstrings = []
Open('embedded.html', '<!--%s-->')
try
  simplecomment#Toggle(3, 3)
catch
  assert_report('a mistyped commentstring table threw: ' .. v:exception)
endtry
assert_equal('    // let x = 1;', getline(3))

g:simplecomment_commentstrings = {js: '/* %s */'}
Open('embedded.html', '<!--%s-->')
simplecomment#Toggle(3, 3)
assert_equal('    /* let x = 1; */', getline(3),
  'a documented language alias did not override its canonical entry')
unlet g:simplecomment_commentstrings

# --- health says which of the two answers is in play -----------------------

Open('embedded.html', '<!--%s-->')
cursor(3, 1)
assert_match('context: javascript', execute('SimpleCommentHealth'))
cursor(1, 1)
assert_match('context: buffer (html)', execute('SimpleCommentHealth'))

# A region whose language has no entry says so rather than looking detected.
Open('fenced.md', '<!--%s-->')
cursor(10, 1)
assert_match('context: mermaid (no entry', execute('SimpleCommentHealth'))

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
