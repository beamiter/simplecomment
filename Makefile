.PHONY: check defcompile test context

check: defcompile test context

defcompile:
	vim -N -u NONE -n -es -S tests/defcompile.vim

test:
	vim -N -u NONE -n -es -S tests/vim_smoke.vim

# Unlike the smoke test this one needs $VIMRUNTIME's filetype and syntax files:
# the region it detects comes from the syntax engine.
context:
	vim -N -u NONE -n -es -S tests/context.vim
