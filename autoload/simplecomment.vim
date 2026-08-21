vim9script

var s_operator_pending = false

# Comment markers for languages that turn up as a *region* inside another file
# type.  'commentstring' is buffer-local, so reading it once described the
# buffer and nothing else: a line of JavaScript inside <script> came out as
# `<!-- let x = 1; -->`, a CSS rule inside <style> the same, and a line inside
# a ```rust fence in Markdown too.  None of those compile.  These entries are
# consulted only for a range that sits inside a region whose language differs
# from the buffer's own; everywhere else the buffer's 'commentstring' still
# wins, so a user who set it by hand keeps exactly what they set.
#
# g:simplecomment_commentstrings is merged over this table rather than
# replacing it, so overriding one language does not cost the others.  Setting
# an entry to an empty string puts that language back on the buffer's
# 'commentstring'.
#
# A language missing from the table is not a guess waiting to happen: an
# unknown region falls back to the buffer's 'commentstring', which is what
# every range did before context was detected at all.  That is why JSON is
# absent -- JSON has no comment syntax, so there is no right answer to record.
const DEFAULT_COMMENTSTRINGS = {
  c: '/* %s */',
  cpp: '// %s',
  css: '/* %s */',
  go: '// %s',
  html: '<!-- %s -->',
  java: '// %s',
  javascript: '// %s',
  jsx: '{/* %s */}',
  lua: '-- %s',
  markdown: '<!-- %s -->',
  perl: '# %s',
  php: '// %s',
  python: '# %s',
  ruby: '# %s',
  rust: '// %s',
  scss: '// %s',
  sh: '# %s',
  sql: '-- %s',
  toml: '# %s',
  tsx: '{/* %s */}',
  typescript: '// %s',
  vim: '" %s',
  xml: '<!-- %s -->',
  yaml: '# %s',
}

# The other spellings of those languages: the file type names Vim uses and the
# info strings people write on a Markdown fence.  They live apart from the
# table above so that overriding 'javascript' also covers ```js and .jsx files
# -- one entry to change, not three.
const LANGUAGE_ALIASES = {
  bash: 'sh',
  'c++': 'cpp',
  golang: 'go',
  javascriptreact: 'javascript',
  js: 'javascript',
  py: 'python',
  rb: 'ruby',
  rs: 'rust',
  sass: 'scss',
  shell: 'sh',
  ts: 'typescript',
  typescriptreact: 'typescript',
  vimscript: 'vim',
  yml: 'yaml',
  zsh: 'sh',
}

# Languages a file type writes its *own* code in, even though the group names
# say otherwise.  syntax/cpp.vim sources syntax/c.vim, so `int x = 1;` in a C++
# file is cType and resolves to `c`; syntax/scss.vim and syntax/less.vim source
# syntax/css.vim, so `color: red;` is cssTextProp and resolves to `css`.  None
# of those is an embedded region -- it is the buffer's own code -- so the
# buffer's 'commentstring' has to keep winning, exactly as it did before any of
# this existed.
#
# Without the table the group name alone decided, and it decided wrongly twice.
# In a C++ file with 'commentstring' set to `// %s` by hand, `gc` emitted
# `/* int x = 1; */`, which is not what the user asked for, and a line that was
# already `/* something */` looked like it was wearing our markers, so `gc`
# stripped the user's comment instead of commenting the line.  In an SCSS file
# it split one file in two: the selector line stayed `// .a {` because sassX
# named it, the property line under it became `/* color: red; */`.
#
# Keyed on the canonical buffer language, so `sass` arrives here as `scss`.
const HOST_DIALECTS = {
  arduino: ['c', 'cpp'],
  cpp: ['c'],
  cuda: ['c', 'cpp'],
  less: ['css'],
  objc: ['c'],
  objcpp: ['c', 'cpp'],
  scss: ['css'],
  stylus: ['css'],
}

# A fenced Markdown block delimiter, opening or closing.  One pattern for both
# because both matter: the opening one carries the language, and the closing
# one must never be mistaken for it.
# Internal patterns must not inherit the user's 'magic' setting.  In
# particular, under :set nomagic the `*` in a blank-line test becomes literal
# and the escaped `*` in C's /* marker becomes a quantifier.  That made the
# same toggle produce different text according to an unrelated search option.
const FENCE = '\m^\s*\%(`\{3,}\|\~\{3,}\)'
const BLANK = '\m^\s*$'

# Rebuilt at the start of every range that detects context, and read by the
# helpers below.  Toggle() is a synchronous edit that cannot re-enter itself,
# so script scope is safe here and saves threading four more parameters through
# every helper.  The caches earn their keep because a range asks about the same
# handful of syntax groups and the same one or two languages over and over.
var s_commentstrings: dict<string> = {}
var s_language_keys: list<string> = []
var s_language_of_group: dict<string> = {}
var s_regions: dict<dict<string>> = {}

# Set while walking a run of lines that sit inside one Markdown fence, so the
# upward scan for the fence line happens once per block instead of once per
# line.  See ContextLanguage() for why consecutive in-fence lines are known to
# share a fence.
var s_fence_language = ''
var s_fence_known = false

def Warn(message: string)
  echohl WarningMsg
  echomsg '[SimpleComment] ' .. message
  echohl None
enddef

def Escape(text: string): string
  return escape(text, '\.^$~[]*')
enddef

# Everything Toggle() needs to comment, uncomment and recognise one region,
# built once per range instead of once per line.  Escaping the markers and
# pasting the patterns together inside IsCommented() and UncommentLine() meant
# redoing it for all 100000 lines of a whole-file toggle.  An empty result
# means the format is unusable and the caller has to fall back.
def Region(format: string): dict<string>
  var marker = match(format, '%s')
  if marker < 0
    return {}
  endif
  var left = trim(strpart(format, 0, marker))
  var right = trim(strpart(format, marker + 2))
  if empty(left)
    return {}
  endif
  return {
    prefix: left .. ' ',
    suffix: empty(right) ? '' : ' ' .. right,
    opener: '\m^\s*' .. Escape(left) .. '\%($\|\s\)',
    closer: empty(right) ? '' : '\m' .. Escape(right) .. '\s*$',
    strip_left: '\m^\s*\zs' .. Escape(left) .. '\s\?',
    strip_right: empty(right) ? '' : '\m\s\?' .. Escape(right) .. '\s*$',
  }
enddef

# Callers filter blank lines out before they get here, so this one does not
# test for them again.
def IsCommented(line: string, region: dict<string>): bool
  if line !~# region.opener
    return false
  endif
  return empty(region.closer) || line =~# region.closer
enddef

def CommentLine(line: string, region: dict<string>): string
  if line =~# BLANK
    return line
  endif
  var indent = matchstr(line, '\m^\s*')
  return indent .. region.prefix .. strpart(line, strlen(indent)) .. region.suffix
enddef

def UncommentLine(line: string, region: dict<string>): string
  if line =~# BLANK
    return line
  endif
  # The closer comes off first, and off the line with its indent and opener
  # still on it.  Taking the opener off first turns `  <!-- -->` into `  -->`,
  # and then the closer's optional leading space has nothing left to eat but
  # the indent: an empty comment came back one space -- or, with a tab indent,
  # one whole level -- shallower than it went in.  The opener standing in the
  # way is what keeps that space out of reach.
  var body = empty(region.strip_right) ? line : substitute(line, region.strip_right, '', '')
  return substitute(body, region.strip_left, '', '')
enddef

def Canonical(name: string): string
  return get(LANGUAGE_ALIASES, name, name)
enddef

def BufferLanguage(): string
  return Canonical(tolower(matchstr(&l:filetype, '\m^[^.]*')))
enddef

# Is this language the buffer writing itself rather than a region inside it?
# See HOST_DIALECTS for the two ways that happens and what it cost when only
# the group name got a say.
def OwnLanguage(language: string, buffer_language: string): bool
  if language ==# buffer_language
    return true
  endif
  var dialects: list<string> = get(HOST_DIALECTS, buffer_language, [])
  return index(dialects, language) >= 0
enddef

# Vim's syntax files name their groups after the language they highlight:
# javaScriptIdentifier, cssClassNameDot, markdownCodeBlock, htmlTagN.  That
# convention is the only thing tying a syntax group to a language, so take the
# longest table key the group name starts with.
#
# Longest first, and the character after the key must not be another lowercase
# letter.  Both rules earn their keep: without the length order
# javaScriptIdentifier resolves to `java` and JavaScript gets commented with
# Java's markers, and without the boundary rule `c` claims cssStyle and `js`
# claims jsonString.
def LanguageOfGroup(group: string): string
  if has_key(s_language_of_group, group)
    return s_language_of_group[group]
  endif
  var lowered = tolower(group)
  var language = ''
  for key in s_language_keys
    if stridx(lowered, key) == 0 && strpart(group, strlen(key), 1) !~# '\m^\l'
      language = Canonical(key)
      break
    endif
  endfor
  s_language_of_group[group] = language
  return language
enddef

# Markdown's syntax file does not name the language of a fenced block: unless
# the user set g:markdown_fenced_languages the whole block is one
# markdownCodeBlock, so the fence line is the only place the language is
# written down.  Scan up to it.
#
# Scanning strictly upward is safe because the caller only asks once the syntax
# stack has said the line is inside a block: the nearest fence above is then
# that block's opening fence.  A closing fence carries no info string, so if
# the scan does land on one -- a line the syntax file counted as code that no
# fence opened -- the answer is 'unknown' and the caller falls back, which is
# the old behaviour rather than a wrong marker.
def FenceLanguage(lnum: number): string
  cursor(lnum, 1)
  var opening = search(FENCE, 'bnW')
  if opening == 0
    return ''
  endif
  var info = matchstr(getline(opening), FENCE .. '\s*\zs[A-Za-z0-9+#._-]\+')
  return Canonical(tolower(info))
enddef

# The language of the region the line starts in, or an empty string when that
# is the buffer's own language or cannot be told.
def ContextLanguage(lnum: number, text: string, buffer_language: string): string
  var col = match(text, '\S') + 1
  var group = synIDattr(synID(lnum, col, 0), 'name')

  # A fence delimiter is not part of the fenced language -- commenting ```rust
  # with Rust's markers would leave the fence half eaten -- so it counts as
  # Markdown and, by clearing the cache, also ends the run of lines that share
  # a fence.  Everything between two delimiters is one block, which is what
  # lets the lines in between reuse the scan.
  if buffer_language ==# 'markdown' && group =~# '\m^markdown\%(Code\|Highlight\)'
    if text =~# FENCE
      s_fence_known = false
      return ''
    endif
    if !s_fence_known
      s_fence_language = FenceLanguage(lnum)
      s_fence_known = true
    endif
    return OwnLanguage(s_fence_language, buffer_language) ? '' : s_fence_language
  endif
  s_fence_known = false

  var language = LanguageOfGroup(group)
  if empty(language)
    # synID() names only the innermost item, and an item we do not recognise
    # nested inside javaScript is still JavaScript, so walk outward.  synstack()
    # costs about twice a synID() call (31 against 16 microseconds per line
    # here), which is why it only runs on the lines where the cheap answer was
    # no answer at all.
    var stack = synstack(lnum, col)
    var index = len(stack) - 1
    while index >= 0 && empty(language)
      language = LanguageOfGroup(synIDattr(stack[index], 'name'))
      index -= 1
    endwhile
  endif
  return OwnLanguage(language, buffer_language) ? '' : language
enddef

def RegionFor(language: string, fallback: dict<string>): dict<string>
  if empty(language)
    return fallback
  endif
  if !has_key(s_regions, language)
    var format = get(s_commentstrings, language, '')
    var region = empty(format) ? {} : Region(format)
    s_regions[language] = empty(region) ? fallback : region
  endif
  return s_regions[language]
enddef

def ContextLimit(): number
  var configured: any = get(g:, 'simplecomment_context_lines', 2000)
  if type(configured) != v:t_number
    return 2000
  endif
  return max([0, configured])
enddef

# Asking the syntax engine costs 4 to 16 microseconds a line here depending on
# the file type -- more than everything else Toggle() does put together -- and
# it can only answer at all for a buffer whose syntax file was loaded.  So ask
# only when there is something to ask, and only for a range short enough that
# the answer arrives inside one redraw: the worst 2000-line range measured here
# (JavaScript inside <script>) took 50 ms all in, and RangeRegion() usually
# stops after one line anyway.  A longer range keeps the buffer's
# 'commentstring', which is both the documented fallback for an unknown context
# and what every range did before.  g:simplecomment_context_lines raises the
# budget, or turns detection off when set to zero.
def Detecting(count: number): bool
  var limit = ContextLimit()
  return limit > 0 && count <= limit
    && exists('g:syntax_on') && !empty(get(b:, 'current_syntax', ''))
enddef

def Prepare()
  s_commentstrings = copy(DEFAULT_COMMENTSTRINGS)
  var configured: any = get(g:, 'simplecomment_commentstrings', {})
  if type(configured) == v:t_dict
    for [name, format] in items(configured)
      if type(format) != v:t_string || empty(name)
        continue
      endif
      # Filetypes, syntax groups and Markdown fence names are canonicalized;
      # configuration keys must take the same path.  Otherwise `{js: ...}` was
      # accepted into the table but never read, because the detected language
      # had already become `javascript` by RegionFor().
      s_commentstrings[Canonical(tolower(name))] = format
    endfor
  endif
  s_language_keys = sort(keys(s_commentstrings) + keys(LANGUAGE_ALIASES),
    (left, right) => strlen(right) - strlen(left))
  s_language_of_group = {}
  s_regions = {}
  s_fence_language = ''
  s_fence_known = false
enddef

# The markers for the whole range: a foreign region's when every non-blank line
# of the range sits in that one region, the buffer's 'commentstring' otherwise.
#
# Unanimity is the point, and it is not timidity.  Giving each line the markers
# of its own region sounds better and is worse -- a range covering a whole
# <script> element comes back as
#
#     <!-- <script> -->
#     // let x = 1;
#     <!-- </script> -->
#
# where the JavaScript line is no longer inside a script element at all: it is
# body text now, and it renders on the page.  A Markdown range that swallows
# its own ``` fence has the same shape, with the code line left outside the
# fence where `//` comments nothing.  When a range crosses a region boundary
# the language being edited is the enclosing one, so the enclosing
# 'commentstring' is the right answer for all of it.
#
# It is also what keeps `gc` its own inverse.  A range that stays inside one
# region leaves that region's delimiters alone, so the second toggle sees the
# same region and takes the markers back off; a range that commented its own
# delimiters would have destroyed the evidence that the lines between them were
# ever JavaScript.
#
# And it is what makes detection affordable: the first non-blank line settles
# it.  If that line is in the buffer's own language the answer is the buffer's
# 'commentstring' whatever the rest of the range says -- agreement means the
# same answer, disagreement means the fallback -- so an ordinary file pays for
# one synID() call no matter how long the range is.
def RangeRegion(start: number, lines: list<string>, fallback: dict<string>): dict<string>
  if !Detecting(len(lines))
    return fallback
  endif
  Prepare()
  var buffer_language = BufferLanguage()
  var language = ''
  var idx = 0
  while idx < len(lines)
    var text = lines[idx]
    if text !~# BLANK
      var found = ContextLanguage(start + idx, text, buffer_language)
      if empty(found)
        return fallback
      endif
      if empty(language)
        language = found
      elseif found !=# language
        return fallback
      endif
    endif
    idx += 1
  endwhile
  return RegionFor(language, fallback)
enddef

export def Toggle(first: number, last: number)
  if !&l:modifiable || &l:readonly
    Warn('current buffer is not writable')
    return
  endif
  var fallback = Region(&l:commentstring)
  if empty(fallback)
    Warn($'no usable commentstring for filetype {&l:filetype}')
    return
  endif
  var start = max([1, first])
  var finish = min([line('$'), last])
  if finish < start
    return
  endif
  var lines = getline(start, finish)
  # Detection moves the cursor to scan for a Markdown fence, so the view is
  # saved around that as well as around setline().
  var view = winsaveview()
  try
    var region = RangeRegion(start, lines, fallback)

    # Uncomment only when every non-blank line is already commented, and stop
    # at the first line that is not: that is the common case when commenting,
    # and the old code filtered the range twice from end to end before it could
    # tell.
    #
    # A line wearing the buffer's own markers counts as commented too, even
    # when the range was detected as a foreign region.  Commenting a Markdown
    # closing fence destroys the fence, so `<!-- ``` -->` comes back detected
    # as part of the block above it, and testing it against Rust's markers
    # alone would have commented it a second time instead of taking the first
    # comment off.
    var remove = true
    var content = false
    for text in lines
      if text !~# BLANK
        content = true
        if !IsCommented(text, region)
            && (region is fallback || !IsCommented(text, fallback))
          remove = false
          break
        endif
      endif
    endfor
    if !content
      return
    endif

    var changed: list<string>
    if !remove
      changed = mapnew(lines, (_, value) => CommentLine(value, region))
    elseif region is fallback
      changed = mapnew(lines, (_, value) => UncommentLine(value, fallback))
    else
      changed = mapnew(lines, (_, value) =>
        UncommentLine(value, IsCommented(value, region) ? region : fallback))
    endif
    # One setline() for the whole range keeps it a single undo block.
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
  &operatorfunc = matchstr(expand('<SID>'), '\m<SNR>\d\+_') .. 'OperatorApply'
  s_operator_pending = true
  feedkeys('g@', 'n')
enddef

export def Visual()
  Toggle(line("'<"), line("'>"))
enddef

# What Toggle() would use on the current line.  The health check exists because
# 'commentstring' is no longer the whole story, and a user who sees the wrong
# markers needs to know whether detection was off, silent, or overruled.
def ContextReport(): string
  var text = getline('.')
  if !Detecting(1)
    return 'off (syntax or g:simplecomment_context_lines)'
  endif
  if text =~# BLANK
    return 'blank line'
  endif
  Prepare()
  var view = winsaveview()
  var language: string
  try
    language = ContextLanguage(line('.'), text, BufferLanguage())
  finally
    winrestview(view)
  endtry
  if empty(language)
    return $'buffer ({&l:filetype})'
  endif
  var format = get(s_commentstrings, language, '')
  if empty(format)
    return $'{language} (no entry, using commentstring)'
  endif
  return $'{language} ({format})'
enddef

export def Health()
  echomsg 'SimpleComment health'
  echomsg $'  commentstring: {empty(&l:commentstring) ? "missing" : &l:commentstring}'
  echomsg $'  context: {ContextReport()}'
  echomsg $'  buffer: {&l:modifiable && !&l:readonly ? "writable" : "read-only"}'
  echomsg $'  operator: {s_operator_pending ? "pending" : "idle"}'
enddef
