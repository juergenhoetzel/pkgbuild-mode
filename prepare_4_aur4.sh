#!/bin/bash
makepkg --printsrcinfo >> .SRCINFO
git add .SRCINFO PKGBUILD
git commit -m  "$1"
git push
