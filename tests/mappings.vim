vim9script

# Regression tests for the default-mapping guard.
#
# plugin/simplecomment.vim used to install gc/gcc/{Visual}gc unconditionally,
# so it overwrote whatever the user had already bound to those keys.  Because
# plugin/ files load after vimrc but before a VimEnter hook, whether the user's
# mapping or the plugin's survived depended entirely on where the user had
# written it -- the same key behaved differently for two people who had made the
# same choice.  Nothing reported the loss either: only `:verbose nmap gc` showed
# it.  Seventeen other default mappings in the suite are installed only after
# maparg() confirms the key is free, and simpleclipboard/simpletreesitter add
# hasmapto() so a user who routed the <Plug> target to a key of their own does
# not also get the default key taken.  This file holds that shape in place.
#
# The guard runs exactly once, while the plugin file is being sourced, so each
# scenario has to arrange the mappings it cares about and then load the plugin
# afresh -- which is why this is its own Vim rather than part of vim_smoke.vim.

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
const PLUGIN = ROOT .. '/plugin/simplecomment.vim'

# A plugin file loads once per session; the load guard has to come off for the
# next scenario to get a fresh install.
def Load()
  if exists('g:loaded_simplecomment')
    unlet g:loaded_simplecomment
  endif
  execute 'source ' .. fnameescape(PLUGIN)
enddef

const DEFAULT_KEYS = [['gc', 'n'], ['gcc', 'n'], ['gc', 'x']]

def ClearMaps()
  for [lhs, mode] in DEFAULT_KEYS
    if maparg(lhs, mode) !=# ''
      execute mode .. 'unmap ' .. lhs
    endif
  endfor
enddef

# --- free keys still get the defaults --------------------------------------
#
# The guard has to leave the normal case alone: a user who has bound none of
# these keys gets gc, gcc and visual gc exactly as documented.  This is also
# what proves hasmapto() is not matching the <Plug> definitions themselves --
# their right-hand sides are <ScriptCmd> calls, not <Plug> names, so a false
# positive here would leave every default key unmapped.

ClearMaps()
Load()
assert_match('simplecomment-operator', maparg('gc', 'n'),
  'gc was not installed on a free key')
assert_match('simplecomment-toggle-line', maparg('gcc', 'n'),
  'gcc was not installed on a free key')
assert_match('simplecomment-toggle', maparg('gc', 'x'),
  'visual gc was not installed on a free key')

# --- a key the user already owns is left alone ------------------------------

ClearMaps()
nnoremap gc :echo "user owns gc"<CR>
nnoremap gcc :echo "user owns gcc"<CR>
xnoremap gc :echo "user owns visual gc"<CR>
Load()
assert_match('user owns gc', maparg('gc', 'n'),
  'the default overwrote a normal-mode gc the user had already bound')
assert_match('user owns gcc', maparg('gcc', 'n'),
  'the default overwrote a normal-mode gcc the user had already bound')
assert_match('user owns visual gc', maparg('gc', 'x'),
  'the default overwrote a visual-mode gc the user had already bound')

# Each key is judged on its own: taking gcc does not cost the user gc, and
# maparg() is an exact-match lookup, so a bound gcc never makes gc look busy.
ClearMaps()
nnoremap gcc :echo "user owns gcc"<CR>
Load()
assert_match('user owns gcc', maparg('gcc', 'n'),
  'gcc was overwritten when only gcc was bound')
assert_match('simplecomment-operator', maparg('gc', 'n'),
  'gc was skipped because an unrelated key, gcc, was bound')

# Modes are judged on their own too: a visual-mode gc of the user's does not
# stop the normal-mode default, and vice versa.
ClearMaps()
xnoremap gc :echo "user owns visual gc"<CR>
Load()
assert_match('user owns visual gc', maparg('gc', 'x'),
  'visual gc was overwritten')
assert_match('simplecomment-operator', maparg('gc', 'n'),
  'normal gc was skipped because visual gc was bound')

# --- a <Plug> target the user has routed elsewhere --------------------------
#
# Someone who has put the operator on a key of their own has chosen where it
# lives; the default key is not additionally taken on their behalf.

ClearMaps()
nmap <F9> <Plug>(simplecomment-operator)
Load()
assert_equal('', maparg('gc', 'n'),
  'gc was installed even though the user had routed the operator to <F9>')
# The other two targets are untouched by that choice and still get their keys.
assert_match('simplecomment-toggle-line', maparg('gcc', 'n'),
  'gcc was skipped because a different <Plug> target was already routed')
assert_match('simplecomment-toggle', maparg('gc', 'x'),
  'visual gc was skipped because a different <Plug> target was already routed')
nunmap <F9>

# The names overlap as prefixes -- <Plug>(simplecomment-toggle) is a prefix of
# <Plug>(simplecomment-toggle-line) up to the closing paren -- so routing the
# line toggle must not be read as routing the visual toggle.
ClearMaps()
nmap <F9> <Plug>(simplecomment-toggle-line)
Load()
assert_equal('', maparg('gcc', 'n'),
  'gcc was installed even though the user had routed the line toggle to <F9>')
assert_match('simplecomment-toggle', maparg('gc', 'x'),
  'visual gc was skipped by a hasmapto() prefix collision with the line toggle')
nunmap <F9>

# --- a mistyped opt-in must not abort plugin load ----------------------------
#
# plugin/simplecomment.vim is vim9script, so `if g:simplecomment_default_mappings`
# with a list or the string '0' is E745 / E1135 at source time and the <Plug>
# maps never exist.  Invalid types fall back to the documented default (on).

ClearMaps()
g:simplecomment_default_mappings = '0'
try
  Load()
catch
  assert_report('a string default-mappings flag threw at load: ' .. v:exception)
endtry
assert_match('simplecomment-operator', maparg('gc', 'n'),
  'a mistyped mappings flag skipped the defaults instead of falling back')
g:simplecomment_default_mappings = []
try
  Load()
catch
  assert_report('a list default-mappings flag threw at load: ' .. v:exception)
endtry
assert_match('simplecomment-toggle-line', maparg('gcc', 'n'),
  'a list mappings flag skipped gcc')
g:simplecomment_default_mappings = 1

# --- the opt-out still installs nothing -------------------------------------

ClearMaps()
g:simplecomment_default_mappings = 0
Load()
for [lhs, mode] in DEFAULT_KEYS
  assert_equal('', maparg(lhs, mode),
    printf('%smap %s was installed with default mappings switched off', mode, lhs))
endfor
g:simplecomment_default_mappings = 1

# The <Plug> mappings are always installed, whatever the defaults do.
assert_match('simplecomment', maparg('<Plug>(simplecomment-operator)', 'n'))
assert_match('simplecomment', maparg('<Plug>(simplecomment-toggle-line)', 'n'))
assert_match('simplecomment', maparg('<Plug>(simplecomment-toggle)', 'x'))

# --- the mappings execute the range the user typed --------------------------
#
# <ScriptCmd> keeps Visual mode active.  Until the mapping explicitly left it,
# '< and '> still named the previous selection: the first visual gc did nothing
# (both marks were zero), and every later one toggled the range selected before
# the current one.
ClearMaps()
Load()
new
setlocal filetype=python
&l:commentstring = '# %s'
setline(1, ['one', 'two', 'three'])
cursor(1, 1)
feedkeys('Vjgc', 'xt')
assert_equal(['# one', '# two', 'three'], getline(1, 3),
  'visual gc used the previous Visual marks instead of the active range')

# feedkeys() appends by default.  Since gc is a prefix of gcc, the motion that
# disambiguates the two mappings is already in typeahead when Operator() runs;
# g@ must be inserted ahead of it or `gcj` executes j first and leaves g@
# pending without changing any text.
setline(1, ['one', 'two', 'three'])
cursor(1, 1)
feedkeys('gcj', 'xt')
assert_equal(['# one', '# two', 'three'], getline(1, 3),
  'gc{motion} put g@ behind the motion in typeahead')
assert_match('operator: idle', execute('SimpleCommentHealth'),
  'a completed gc{motion} left Health reporting operator: pending')
bwipeout!

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
