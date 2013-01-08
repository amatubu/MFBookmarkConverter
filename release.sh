#!/bin/sh

cp BookmarkConverter.pl MFBookmarkConverter/BookmarkConverter.app/Contents/Resources/droplet.PL

rm -f MFBookmarkConverter.zip
zip -r MFBookmarkConverter.zip MFBookmarkConverter

cp MFBookmarkConverter.zip ~/Dropbox/Public/
