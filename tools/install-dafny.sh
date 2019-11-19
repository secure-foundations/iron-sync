#! /bin/bash

set -e
set -x

mkdir .dafny
cd .dafny

git clone https://github.com/boogie-org/boogie
cd boogie
wget https://nuget.org/nuget.exe
mono ./nuget.exe restore Source/Boogie.sln
msbuild /p:Configuration=Release Source/Boogie.sln
cd ..

git clone --branch cpp https://github.com/secure-foundations/dafny.git cpp-dafny
cd dafny
msbuild /p:Configuration=Release Source/Dafny.sln
cd ..

if [ `uname` == "Darwin" ]; then
    wget https://github.com/Z3Prover/z3/releases/download/z3-4.6.0/z3-4.6.0-x64-osx-10.11.6.zip
    unzip z3-4.6.0-x64-osx-10.11.6.zip
    cp -r z3-4.6.0-x64-osx-10.11.6 dafny/Binaries/z3/
elif [ `uname` == "Linux" ]; then
    wget https://github.com/Z3Prover/z3/releases/download/z3-4.6.0/z3-4.6.0-x64-ubuntu-16.04.zip
    unzip z3-4.6.0-x64-ubuntu-16.04.zip
    cp -r z3-4.6.0-x64-ubuntu-16.04 dafny/Binaries/z3/
fi

mkdir bin
echo "#! /bin/bash" > bin/dafny
echo "mono `pwd`/dafny/Binaries/Dafny.exe \"\$@\"" >> bin/dafny
chmod +x bin/dafny

