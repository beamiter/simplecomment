.PHONY: check defcompile test context mappings

check: defcompile test context mappings

defcompile:
	vim -N -u NONE -n -i NONE -es -S tests/defcompile.vim

test:
	vim -N -u NONE -n -i NONE -es -S tests/vim_smoke.vim

# Unlike the smoke test this one needs $VIMRUNTIME's filetype and syntax files:
# the region it detects comes from the syntax engine.
context:
	vim -N -u NONE -n -i NONE -es -S tests/context.vim

# The default-mapping guard runs once, while plugin/simplecomment.vim is being
# sourced, so it can only be observed by a test that arranges the mappings
# first and loads the plugin afterwards.  That is why it is its own Vim rather
# than more of the smoke test, which sources the plugin before it asserts
# anything and so can never see an unloaded state again.
mappings:
	vim -N -u NONE -n -i NONE -es -S tests/mappings.vim
