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
