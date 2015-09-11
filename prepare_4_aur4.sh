#!/bin/bash
mksrcinfo
git add .SRCINFO PKGBUILD
git commit -m  "$1"
git push
