# SimpleComment

A small Vim9 comment operator driven by the buffer-local `commentstring`.

## Commands and mappings

- `:SimpleCommentToggle` toggles a line or range.
- `gcc` toggles the current line.
- `gc{motion}` and visual `gc` toggle a region.
- `<Plug>(simplecomment-toggle-line)`, `<Plug>(simplecomment-operator)` and
  `<Plug>(simplecomment-toggle)` are available when default mappings are off.

Set `g:simplecomment_default_mappings = 0` before loading to keep only the
commands and `<Plug>` mappings. Remote buffers need no special path handling:
the plugin edits the current Vim buffer and lets its owner handle writes.

## Regions

`commentstring` is buffer-local, so on its own it wraps a line of JavaScript
inside `<script>` in `<!-- -->`, and a line inside a ` ```rust ` fence in a
Markdown file too. Neither compiles. SimpleComment asks Vim's syntax engine
what region the range is in first, and uses that language's markers when the
whole range sits in one region that is not the buffer's own language:

```
    let x = 1;             ->     // let x = 1;
    .b { color: red; }     ->     /* .b { color: red; } */
```

A range that crosses a region boundary is being edited as the enclosing
language, so it keeps the buffer's `commentstring` — commenting a whole
`<script>` element line by line with JavaScript markers would leave the code
outside the element, rendering on the page. A context the syntax engine cannot
name is never guessed at; it falls back to `commentstring` as well.

`g:simplecomment_commentstrings` overrides individual languages
(`{javascript: '/* %s */'}`, an empty string to disable one) and
`g:simplecomment_context_lines` caps how long a range may be before detection
is skipped (default 2000, zero to turn it off). `:SimpleCommentHealth` shows
what the current line resolves to. Language aliases such as `js` are accepted
as override keys; invalid option types fall back to the defaults.
