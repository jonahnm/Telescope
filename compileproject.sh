#!/bin/bash

# basebin
cd TelescopeBin

#pluto (rootlesshooks)
cd Pluto
make
cd ../

#jup (jbd) (broken (xpc headers))
cd Jupiter
# make


cd ../..
make
