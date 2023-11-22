precommit:
	perltidy ./my-bookmarks.pl
	perlcritic --brutal ./my-bookmarks.pl
