#! /bin/bash

### Update this commit hash in order to update the version of dafny
### to build Veribetrfs with.

### This script is called as a subroutine from our installer
### and updater scripts, and it serves as the single point to save
### the dafny commit hash compatible with the veribetrfs repository.

### Typically, we'll expect to keep this set to the head of the betr
### branch of our dafny fork.

### When the dafny runtime API on that branch changes, we can update
### our code in this repo while updating this commit hash. Hence,
### this hash should always point to a version of dafny comaptible
### with this version of veribetrfs.

set -e
set -x

# set to betr-concurrent-mod branch
commit=96075c706b6f9808de5fc7b7b7c887f9043958f8
if [ $1 ]; then
   commit=$1
fi

# https://github.com/secure-foundations/dafny.git
git checkout $commit
